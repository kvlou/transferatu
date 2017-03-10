namespace :schedules do
  task :check do
    require "bundler"
    Bundler.require
    require_relative "../initializer"

    SHOGUN_DB = Sequel.connect(ENV['TEMPORARY_SHOGUN_FOLLOWER_URL'])
    YOBUKO_DB = Sequel.connect(ENV['YOBUKO_FOLLOWER_URL'])

    class TakenWithOtherAppError < StandardError; end

    def from_database(transfer)
      URI.parse(transfer.from_url).path[1..-1]
    end

    def shogun_database_name_valid?(app_uuid, schedule_name, database_name)
      SHOGUN_DB.fetch(<<-EOF, app_uuid: app_uuid, schedule_name: schedule_name, database_name: database_name).first[:valid]
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
      YOBUKO_DB.fetch(<<-EOF, app_uuid: app_uuid, schedule_name: schedule_name, database_name: database_name).first[:valid]
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

    def shogun_same_app_uuid?(app_uuid, database_name)
      SHOGUN_DB.fetch(<<-EOF, app_uuid: app_uuid, database_name: database_name).first[:same]
SELECT
  count(*) > 0 AS same
FROM
  timelines t
    INNER JOIN services s ON t.id = s.timeline_id
    INNER JOIN formations f ON f.uuid = s.formation_id
    INNER JOIN heroku_resources hr ON hr.formation_id = f.uuid
WHERE
  t.database_name = :database_name
    AND hr.app_uuid = :app_uuid
EOF
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
        # for now, return false here and will check about resource_transfers
        # later with new way
        false
      else
        apps.uniq.length == 1
      end
    end

    def yobuko_owner_uniq_check(s, from_urls)
      owners = []
      need_to_check_resource_transfers = false
      from_urls.each do |furl|
        owner = YOBUKO_DB.fetch(<<-EOF, hostname: furl.host, database: furl.path[1..-1]).first
SELECT
  hr.email AS owner
FROM
  heroku_resources hr
    INNER JOIN resources r ON hr.resource_id = r.id
    INNER JOIN participants p ON r.participant_id = p.id
WHERE
  p.hostname = :hostname
    AND r.database = :database
EOF
        if owner
          owners << owner[:owner]
        else
          # if you can't get an app here, it means that schedule has some
          # resource that is not discovered in yobuko.
          # this very likely means that there was some resource transfer
          # happened, so gonna check resource transfer
          need_to_check_resource_transfers = true
        end
      end

      if need_to_check_resource_transfers
        # for now, return false here and will check about resource_transfers
        # later with new way
        false
      else
        owners.uniq.length == 1
      end
    end

    def yobuko_resource_transfer_dbnames(s)
      # even though you had many resource transfers in the past,
      # due to the way how resource transfer works, it will always have the
      # same resource_id
      resource_ids = YOBUKO_DB[:heroku_resources].where(app_uuid: s.group.name).all.map { |hr| hr[:resource_id] }
      rt_dbnames = []

      resource_ids.each do |resource_id|
        resource_transfers = YOBUKO_DB[:resource_transfers].where(resource_id: resource_id).all
        resource_transfers.each do |rt|
          # for some reason, sometimes yobuko has some transfer_id that is not uuid
          # skip for that case
          next unless UUID.validate(rt[:transferatu_transfer_id])
          t = Transferatu::Transfer[rt[:transferatu_transfer_id]]
          rt_dbnames << from_database(t)
        end
      end

      rt_dbnames.uniq.compact
    end

    def yobuko_check(s)
      from_urls = s.transfers.map { |x| x.from_url }.uniq.compact.map { |u| URI.parse(u) }

      result = yobuko_app_uniq_check(s, from_urls)

      unless result
        result = yobuko_owner_uniq_check(s, from_urls)
      end

      result
    end

    def yobuko_shogun_crosscheck(s)
      dbnames = s.transfers.map { |xfer| from_database(xfer) }.uniq.compact
      # remove dbnames that are associated with shogun
      dbnames.reject! { |dbname| shogun_database_name_valid?(s.group.name, s.name, dbname) }
      # remove dbnames that have the same app_uuid
      dbnames.reject! { |dbname| shogun_same_app_uuid?(s.group.name, dbname) }
      # remove dbnames that are associated with yobuko
      dbnames.reject! { |dbname| yobuko_database_name_valid?(s.group.name, s.name, dbname) }
      # get all dbnames from yobuko resource transfers
      resource_transfer_dbnames = yobuko_resource_transfer_dbnames(s)
      (dbnames - resource_transfer_dbnames).empty?
    end

    def check_only_one_dbname(s)
      # **not used at the moment**
      # this method checks if there is any database name shows up
      # among many transfers, only one time
      # if so, that database likely does not belong to the schedule
      all_dbnames = s.transfers.map { |xfer| from_database(xfer) }.compact
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

    def get_current_heroku_resource_info(s)
      app_uuid = s.group.name
      schedule_name = s.name
      # heroku_resources table in yobuko has the info like app (app name), email (owner email)
      YOBUKO_DB.fetch(<<-EOF, app_uuid: app_uuid, schedule_name: schedule_name).first
SELECT
  hr.*
FROM
  heroku_resources hr
    INNER JOIN resources r ON hr.resource_id = r.id
WHERE
  hr.app_uuid = :app_uuid
    AND (hr.attachment_name = :schedule_name OR hr.aux_attachment_names @> ARRAY[:schedule_name])
EOF
    end

    def get_heroku_resource_from_url(from_url)
      hostname = from_url.host
      database = from_url.path[1..-1]

      YOBUKO_DB.fetch(<<-EOF, hostname: hostname, database: database).first
SELECT
  hr.*
FROM
  heroku_resources hr
    INNER JOIN resources r ON hr.resource_id = r.id
    INNER JOIN participants p ON r.participant_id = p.id
WHERE
  p.hostname = :hostname
    AND r.database = :database
EOF
    end

    def check_affected(s)
      # this method checks the current schedule's app name and owner,
      # compares with the db that was taken a backup only one time among
      # all transfers.

      # only checks yobuko for now
      return false if shogun_schedule?(s)

      heroku_resource = get_current_heroku_resource_info(s)
      # it's possible that you can't find heroku_resource, especially with deleted schedules
      # just raise an error so that it can be checked manually
      raise ArgumentError, "Couldn't find heroku_resouce of this schedule. Please check manually" unless heroku_resource
      app_name = heroku_resource[:app]
      owner_email = heroku_resource[:email]

      all_dbnames = s.transfers.map { |xfer| from_database(xfer) }.compact
      dbnames_count = {}
      all_dbnames.each do |dbname|
        dbnames_count[dbname] = dbnames_count.fetch(dbname, 0) + 1
      end

      errors = []
      dbnames_count.select! { |k, v| v == 1 }

      unless dbnames_count.empty?
        single_db_transfers = s.transfers.select { |t| dbnames_count.keys.include? from_database(t) }

        hr_not_found = []
        single_db_transfers.each do |transfer|
          from_url = URI.parse(transfer.from_url)
          hr = YOBUKO_DB[:heroku_resources].where(resource_url: from_url.to_s).first
          hr ||= get_heroku_resource_from_url(from_url)
          if hr
            # cross check with the current heroku resource
            unless app_name == hr[:app] || owner_email == hr[:email]
              # nothing is matching to the current resource, it is affected by the issue
              errors << "The transfer #{transfer.uuid} is associated with #{hr[:app]} (#{hr[:email]}), \
              whereas the schedule is with #{app_name} (#{owner_email})."
            end
          else
            # if you can't find hr, that means it's either shogun db,
            # or the db that was moved by resource transfer
            # let's not raise error here yet, and add some message for now
            hr_not_found << "The transfer #{transfer.uuid} is associated with #{hr[:app]} (#{hr[:email]}), \
            whereas the schedule is not associated with it (but wasn't able to find in yobuko: \
            #{from_url.host}:#{from_url.port}#{from_url.path}"
          end
        end

        unless hr_not_found.empty?
          if errors.empty?
            # this means that we weren't able to find the associated heroku_resource
            # for any of single_db_transfers, let's now raise error
            raise ArgumentError, hr_not_found.join("\n")
          else
            # this means, this schedule had several single_db_transfers
            # and more than one of them is associated with other apps.
            # let's just assume that the one that wasn't able to find
            # heroku_resource as affected as well
            errors + hr_not_found
          end
        end
      end

      if errors.empty?
        # mark as false for now
        false
      else
        raise TakenWithOtherAppError, errors.join("\n")
      end
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
      dbnames = s.transfers.map { |xfer| from_database(xfer) }.uniq.compact
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
      result || check_affected(s)
    end

    def format_exception(e)
      if e.class == TakenWithOtherAppError
        e.class.name + ": " + e.message
      else
        e.class.name + ": " + e.message + "\n" + e.backtrace.join("\n")
      end
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
      # we've patched at 2017-03-02 19:59 UTC, so it's safe to assume that
      # any schedules that are created after 2017-03-03 are unaffected by this
      next_batch = Transferatu::ScheduleCheck.unverified(by: Time.new(2017, 3, 3)).all
      break if next_batch.empty?

      verify_schedules(next_batch)
    end
  end
end
