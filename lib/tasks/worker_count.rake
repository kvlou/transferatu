namespace :worker_count do
  task :change, [:new_count] do |t, args|
    require "bundler"
    Bundler.require
    require_relative "../initializer"

    unless args[:new_count]
      raise StandardError, "Usage: bundle exec rake worker_count:change[100]"
    end

    heroku = PlatformAPI.connect_oauth(Config.heroku_api_token)
    heroku_app_name = Config.heroku_app_name
    new_value = { WORKER_COUNT: args[:new_count] }

    heroku.config_var.update(heroku_app_name, new_value)
  end
end
