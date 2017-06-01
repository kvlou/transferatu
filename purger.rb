require "bundler"
Bundler.require

require "./lib/initializer"

$stdout.sync = true

loop do
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
  sleep 2.minute
end
