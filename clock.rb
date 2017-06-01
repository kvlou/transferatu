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
end
