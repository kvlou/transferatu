require "net/ssh/gateway"
module Transferatu
  class TransferWorker
    def initialize(status)
      @status = status
    end

    def perform(transfer)
      t = transfer
      maybe_tunnel(t.to_url, t.to_bastion_host, t.to_bastion_key) do |to_url|
        maybe_tunnel(t.from_url, t.from_bastion_host, t.from_bastion_key) do |from_url|
          perform_inside_tunnel(transfer, from_url, to_url)
        end
      end
    end

    def perform_inside_tunnel(transfer, from_url, to_url)
      @status.update(transfer: transfer)

      # TODO: break this out into an Executor mediator?

      runner = nil
      begin
        runner = RunnerFactory.runner_for(transfer, from_url, to_url)
        # We don't want to make the failure messages here too
        # explicit, since they may pertain to the internal details of
        # the service and not be useful to end-users trying to
        # diagnose failures. As we learn the more common specific
        # failure modes, we should address them more directly and
        # communicate them concretely.
      rescue Sequel::DatabaseError => e
        fail_transfer(transfer,
                      "Could not connect to database to initialize transfer",
                      e)
      rescue StandardError => e
        Rollbar.error(e, transfer_id: transfer.uuid)
        fail_transfer(transfer,
                      "Could not initialize transfer",
                      e)
      end

      return unless runner

      # Sequel model objects are not safe for concurrent access, so
      # make sure we give the progress thread its own copy
      xfer_id = transfer.uuid
      progress_thr = Thread.new do
        begin
          xfer = Transfer[xfer_id]
          while xfer.in_progress? do
            xfer.mark_progress(runner.processed_bytes)
            # Nothing to change, but we want to update updated_at to
            # report in
            @status.save
            sleep 5
            xfer.reload
          end
          if xfer.canceled?
            runner.cancel
          else
            # Flag final progress
            xfer.mark_progress(runner.processed_bytes)
          end
        rescue StandardError => e
          Rollbar.error(e, transfer_id: xfer.uuid)
          raise
        end
      end

      # Do not run the transfer if it's already canceled at this point
      return if transfer.canceled?

      begin
        Rollbar.scoped(transfer_id: xfer_id) do
          result = runner.run_transfer
          if result
            transfer.complete
          else
            transfer.fail
          end
          transfer.update(warnings: runner.warnings) if runner.warnings
        end
      rescue Transfer::AlreadyFailed
        # ignore; if the transfer was canceled or otherwise failed
        # out of band, there's not much for us to do
      end

      progress_thr.join

      # TODO: fix this tomorrow
      # This was disabled because eviction can evict manual backups
      # Transferatu::Mediators::Transfers::Evictor.run(transfer: transfer)
    ensure
      @status.update(transfer: nil)
    end

    def wait(count: 0)
      # randomize sleep to avoid lock-stepping workers into a single
      # sequence
      sleep [2**count, 60].min + 4 * rand
      # See above: we want to make sure we show progress when there's
      # nothing to do.
      @status.save
    end

    private

    def maybe_tunnel(transfer_url, bastion_host, bastion_key)
      if bastion_host && bastion_key && !bastion_host.empty? && !bastion_key.empty?
        begin
          uri = URI.parse(transfer_url)
          gateway = Net::SSH::Gateway.new(bastion_host, 'bastion',
            paranoid: false, timeout: 15, key_data: [bastion_key])
          local_port = rand(65535 - 49152) + 49152
          gateway.open(uri.host, uri.port, local_port) do |actual_local_port|
            uri.host = 'localhost'
            uri.port = actual_local_port
            yield uri.to_s
          end
        rescue Errno::EADDRINUSE
          # Get a new random port if a local binding was not possible.
          gateway && gateway.shutdown!
          gateway = nil
          retry
        ensure
          gateway && gateway.shutdown!
        end
      else
        yield(transfer_url)
      end
    end

    def fail_transfer(transfer, message, exception)
      transfer.fail
      transfer.log message
      transfer.log exception.message, level: :internal
      exception.backtrace.each do |line|
        transfer.log line, level: :internal
      end
    end
  end
end
