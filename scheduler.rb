require "bundler"
Bundler.require

require "./lib/initializer"
require "clockwork"

$stdout.sync = true

module Clockwork
  # Current peak of the scheduled backups is ~4000 in one hour. In addition
  # to that,  we have manual backups.
  # Let's say that we need to dump 4000 jobs per hour, which is about
  # 350 every 5 minutes. For now, set it to 400 to see how it goes.

  # Any scheduled job that should have happened in the last 12 hours,
  # but has not been run in the last 12 hours is eligible

  every(5.minutes, "run-scheduled-transfers") do
    resolver = Transferatu::ScheduleResolver.new
    processor = Transferatu::ScheduleProcessor.new(resolver)
    manager = Transferatu::ScheduleManager.new(processor)

    scheduled_time = Time.now

    Pliny.log(task: 'run-scheduled-transfers', scheduled_for: scheduled_time) do
      manager.run_schedules(scheduled_time, 400)
    end
  end
end
