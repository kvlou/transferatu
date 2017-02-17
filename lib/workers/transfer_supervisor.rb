module Transferatu
  module TransferSupervisor
    def self.run
      started_at = Time.now
      status = Transferatu::WorkerStatus.create
      worker = TransferWorker.new(status)
      loop do
        if AppStatus.updated_at > started_at
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
