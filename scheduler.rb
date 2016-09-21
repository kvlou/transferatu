require "bundler"
Bundler.require

require "./lib/initializer"
require "clockwork"

$stdout.sync = true

module Clockwork
  # Originally: Dump 250 jobs in the queue every 5 minutes

  # That's 250*12 or 3000 an hour. Peak is ~9000 jobs in one hour
  # We will need to dump at least 850 every 5 minutes to achieve throughput

  # Any scheduled job that should have happened in the last 12 hours,
  # but has not been run in the last 12 hours is eligible

  every(5.minutes, "run-scheduled-transfers") do
    resolver = Transferatu::ScheduleResolver.new
    processor = Transferatu::ScheduleProcessor.new(resolver)
    manager = Transferatu::ScheduleManager.new(processor)

    scheduled_time = Time.now

    Pliny.log(task: 'run-scheduled-transfers', scheduled_for: scheduled_time) do
      manager.run_schedules(scheduled_time, 1000)
    end
  end
end
