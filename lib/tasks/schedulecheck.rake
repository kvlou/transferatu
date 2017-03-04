namespace :schedules do
  task :check do
    require "bundler"
    Bundler.require
    require_relative "../initializer"

    SHOGUN_DB = Sequel.connect(ENV['TEMPORARY_SHOGUN_FOLLOWER_URL'])

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

    def from_database(transfer)
      URI.parse(transfer.from_url).path[1..-1]
    end

    def shogun_schedule?(s)
      URI.parse(s.callback_url).host == 'shogun.heroku.com'
    rescue
      false
    end

    def schedule_okay?(s)
      dbnames = s.transfers.map { |xfer| from_database(xfer) }.uniq
      if dbnames.empty?
        true
      elsif shogun_schedule?(s)
        dbnames.all? { |dbname| shogun_database_name_valid?(s.group.name, s.name, dbname) }
      elsif dbnames.count == 1
        res = Transferatu::ScheduleResolver.new
        resolved_dbname = URI.parse(res.resolve(s)['from_url']).path
        dbnames.first == resolved_dbname
      else
        false
      end
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
