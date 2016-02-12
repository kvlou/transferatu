module Transferatu
  class ScheduleManager
    def initialize(processor)
      @processor = processor
    end

    def run_schedules(schedule_time, batch_size)
      schedules = Schedule.pending_for(schedule_time, limit: batch_size).all
      Parallel.each(schedules, in_threads: 8) do |s|
        process_schedule(s)
      end
    end

    private

    def process_schedule(s)
      retrying = false
      begin
        @processor.process(s)
      rescue StandardError => e
        if retrying
          Rollbar.error(e, schedule_id: s.uuid)
          s.group.log "Could not create scheduled transfer for #{s.name}"
          s.mark_executed
        else
          retrying = true
          retry
        end
      end
    end
  end
end
