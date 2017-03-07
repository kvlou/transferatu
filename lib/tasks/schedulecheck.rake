namespace :schedules do
  task :check do
    require "bundler"
    Bundler.require
    require_relative "../initializer"

    SHOGUN_DB = Sequel.connect(ENV['TEMPORARY_SHOGUN_FOLLOWER_URL'])
    YOBUKO_DB = Sequel.connect(ENV['YOBUKO_FOLLOWER_URL'])

    def shogun_database_name_valid?(app_uuid, schedule_name, database_name)
      valid = SHOGUN_DB.fetch(<<-EOF, app_uuid: app_uuid, schedule_name: schedule_name, database_name: database_name).first[:valid]
SELECT
  count(*) > 0 AS valid
FROM
  heroku_resources hr
    INNER JOIN services s ON hr.formation_id = s.formation_id
    INNER JOIN timelines t ON s.timeline_id = t.id
WHERE
  hr.app_uuid = :app_uuid
    AND (hr.attachment_name = :schedule_name OR hr.aux_attachment_names @> ARRAY[:schedule_name])
    AND t.database_name = :database_name
EOF
    end

    def yobuko_database_name_valid?(app_uuid, schedule_name, database_name)
      valid = YOBUKO_DB.fetch(<<-EOF, app_uuid: app_uuid, schedule_name: schedule_name, database_name: database_name).first[:valid]
SELECT
  count(*) > 0 AS valid
FROM
  heroku_resources hr
    INNER JOIN resources r ON hr.resource_id = r.id
WHERE
  hr.app_uuid = :app_uuid
    AND r.database = :database_name
EOF
    end

    def from_database(transfer)
      URI.parse(transfer.from_url).path[1..-1]
    end

    def yobuko_app_uniq_check(s, from_urls)
      apps = []
      need_to_check_resource_transfers = false
      from_urls.each do |furl|
        app = YOBUKO_DB.fetch(<<-EOF, hostname: furl.host, database: furl.path[1..-1]).first
SELECT
  hr.app AS app
FROM
  heroku_resources hr
    INNER JOIN resources r ON hr.resource_id = r.id
    INNER JOIN participants p ON r.participant_id = p.id
WHERE
  p.hostname = :hostname
    AND r.database = :database
EOF
        if app
          apps << app[:app]
        else
          # if you can't get an app here, it means that schedule has some
          # resource that is not discovered in yobuko.
          # this very likely means that there was some resource transfer
          # happened, so gonna check resource transfer
          need_to_check_resource_transfers = true
        end
      end

      if need_to_check_resource_transfers
        yobuko_resource_transfer_check(s, from_urls)
      else
        apps.uniq.length == 1
      end
    end

    def get_current_resource_id(app_uuid, schedule_name)
      resource = YOBUKO_DB.fetch(<<-EOF, app_uuid: app_uuid, schedule_name: schedule_name).first[:resource_id]
SELECT
  hr.resource_id
FROM
  heroku_resources hr
    INNER JOIN resources r ON hr.resource_id = r.id
WHERE
  hr.app_uuid = :app_uuid
    AND (hr.attachment_name = :schedule_name OR hr.aux_attachment_names @> ARRAY[:schedule_name])
    AND r.state NOT IN ('deprovisioning', 'deprovision_grace_period', 'deprovisioned')
EOF
    end

    def yobuko_resource_transfer_check(s, from_urls)
      # even though you had many resource transfers in the past,
      # due to the way how resource transfer works, it will always have the
      # same resource_id
      resource_id = get_current_resource_id(s.group.name, s.name)

      hosts_from_transfers = from_urls.map(&:host).uniq
      hosts_from_rt = []

      resource_transfers = YOBUKO_DB[:resource_transfers].where(resource_id: resource_id).all
      resource_transfers.each do |rt|
        ids = [rt[:source_participant_id], rt[:target_participant_id]]
        hosts_from_rt << YOBUKO_DB[:participants].where(id: ids).all.map { |p| p[:hostname] }.flatten
      end
      hosts_from_rt = hosts_from_rt.flatten.uniq

      (hosts_from_transfers - hosts_from_rt).length == 0
    end

    def yobuko_check(s)
      from_urls = s.transfers.map { |x| x.from_url }.uniq.map { |u| URI.parse(u) }

      yobuko_app_uniq_check(s, from_urls)
    end

    def yobuko_shogun_crosscheck(s)
      dbnames = s.transfers.map { |xfer| from_database(xfer) }.uniq
      # remove dbnames that are associated with shogun
      dbnames.reject! { |dbname| shogun_database_name_valid?(s.group.name, s.name, dbname) }
      # remove dbnames that are associated with yobuko
      dbnames.reject! { |dbname| yobuko_database_name_valid?(s.group.name, s.name, dbname) }
      dbnames.empty?
    end

    def check_only_one_dbname(s)
      # this method checks if there is any database name shows up
      # among many transfers, only one time
      # if so, that database likely does not belong to the schedule
      all_dbnames = s.transfers.map { |xfer| from_database(xfer) }
      dbnames_count = {}
      all_dbnames.each do |dbname|
        dbnames_count[dbname] = dbnames_count.fetch(dbname, 0) + 1
      end

      if dbnames_count.select { |k, v| v == 1 }.count > 0
        raise ArgumentError, "There is database name that is only used once among schedules: #{dbnames_count}"
      end

      # this method is only called for false things, so return false anyways
      false
    end

    def yobuko_schedule?(s)
      URI.parse(s.callback_url).host == 'yobuko.heroku.com'
    rescue
      false
    end

    def shogun_schedule?(s)
      URI.parse(s.callback_url).host == 'shogun.heroku.com'
    rescue
      false
    end

    def schedule_okay?(s)
      dbnames = s.transfers.map { |xfer| from_database(xfer) }.uniq
      result = if dbnames.empty?
        true
      elsif shogun_schedule?(s)
        dbnames.all? { |dbname| shogun_database_name_valid?(s.group.name, s.name, dbname) }
      elsif yobuko_schedule?(s)
        yobuko_check(s)
      elsif dbnames.count == 1
        res = Transferatu::ScheduleResolver.new
        resolved_dbname = URI.parse(res.resolve(s)['from_url']).path
        dbnames.first == resolved_dbname
      else
        false
      end

      # if result is false, do crosscheck
      result = yobuko_shogun_crosscheck(s) unless result

      # if result is still false, check only one dbname as additional info
      result || check_only_one_dbname(s)
    end

    def format_exception(e)
      e.class.name + ": " + e.message + "\n" + e.backtrace.join("\n")
    end

    def verify_schedules(schedules)
      schedules.each do |s|
        begin
          okay = schedule_okay?(s)
          Transferatu::ScheduleCheck.create(schedule_id: s.uuid, okay: okay)
        rescue => e
          Transferatu::ScheduleCheck.create(schedule_id: s.uuid, notes: format_exception(e))
        end
      end
    end

    loop do
      next_batch = Transferatu::ScheduleCheck.unverified.all
      break if next_batch.empty?

      verify_schedules(next_batch)
    end
  end
end
