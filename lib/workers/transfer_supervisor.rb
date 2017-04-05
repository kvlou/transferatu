module Transferatu
  module TransferSupervisor
    def self.run
      started_at = Time.now
      status = Transferatu::WorkerStatus.create
      worker = TransferWorker.new(status)
      loop do
        # Currently we're updating updated_at every 4 hours, so this is going
        # to be "true" and worker one-off dyno will exit pretty much every 4
        # hours. This 4 hours is to prevent any backups get killed in the
        # middle (e.g. if the backup started running the 23 hours since the
        # dyno was booted and takes more than 1 hour, likely it'll get killed
        # in the middle due to the 24 hours dyno life cycle).
        # To avoid shutting down one-off workers at the same time, add
        # some jitters here. With this, worker one-off dyno will exit between
        # 4 and 6 hours.
        if AppStatus.updated_at - (2.hours * rand) > started_at
          Pliny.log(app: Config.heroku_app_name,
                    method: 'TransferSupervisor.run', step: 'stale-worker-exiting')
          break
        end
        if AppStatus.quiesced?
          # update status even when quiesced so we don't go around
          # killing innocent workers
          status.save
          sleep 5
        else
          run_next(worker)
        end
      end
    end

    def self.run_next(worker)
      @count ||= 0
      transfer = begin
                   Transfer.begin_next_pending
                 rescue Sequel::SerializationFailure
                   # ignore; wait and try again
                 end
      if transfer
        @count = 0
        if transfer.options["trace"]
          Transferatu::ResourceUsage.tracking(transfer.uuid,
                                              transfer.from_type,
                                              transfer.to_type,
                                              'ruby') do
            worker.perform(transfer)
          end
        else
          worker.perform(transfer)
        end
      else
        @count += 1
        worker.wait count: @count
      end
    end
  end
end
