require "bundler"
Bundler.require

require "./lib/initializer"
require "clockwork"

$stdout.sync = true

module Clockwork
  every(3.minute, "top-off-workers") do
    Pliny.log(app: Config.heroku_app_name, task: 'top-off-workers') do
      Transferatu::WorkerManager.new.check_workers
    end
  end

  every(1.minute, "log-metrics") do
    pending_xfer_count = Transferatu::Transfer.pending.count
    active_xfer_count = Transferatu::Transfer.in_progress.count
    Pliny.log(app: Config.heroku_app_name,
              "sample#pending_xfer_count": pending_xfer_count,
              "sample#active_xfer_count": active_xfer_count)
  end

  every(4.hours, "mark-restart") do
    Transferatu::AppStatus.mark_update
  end

  every(30.minute, "run-purger") do
    # TODO: move out to separate worker if this is not keeping up
    started_at = Time.now
    succeeded = 0
    failed = 0
    Transferatu::Transfer.purgeable.limit(5000).all.each do |xfer|
      begin
        Transferatu::Mediators::Transfers::Purger.run(transfer: xfer)
        succeeded += 1
      rescue StandardError => e
        failed += 1
        Rollbar.error(e, transfer_id: xfer.uuid)
      end
    end
    duration = Time.now - started_at
    Pliny.log(app: Config.heroku_app_name,
              "sample#purge_duration": duration,
              "sample#purge_succeeded": succeeded,
              "sample#purge_failed": failed)
  end
end
