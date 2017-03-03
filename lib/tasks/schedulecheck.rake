namespace :schedules do
  task :check do
    require "bundler"
    Bundler.require
    require_relative "../initializer"

    def schedule_okay?(s)
      dbnames = s.transfers.map { |x| x.from_url }.map { |u| URI.parse(u).path }.uniq
      if dbnames.count > 1
        return false
      end
      res = Transferatu::ScheduleResolver.new
      resolved_dbname = URI.parse(res.resolve(s)['from_url']).path
      dbnames.first == resolved_dbname
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
