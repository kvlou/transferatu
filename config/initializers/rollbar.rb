Rollbar.configure do |config|
  config.access_token = ENV["ROLLBAR_ACCESS_TOKEN"]
  config.environment = ENV['ROLLBAR_ENV'] || 'staging'
  config.use_sucker_punch
  config.scrub_headers |= [
    "Authorization",
    "Cookie",
    "Set-Cookie",
    "X_CSRF_TOKEN",
    "HTTP_X_CSRF_TOKEN",
    "X-Csrf-Token",
  ]
  config.scrub_fields |= [
    :access_token,
    :api_key,
    :authenticity_token,
    :"bouncer.refresh_token",
    :"bouncer.token",
    :confirm_password,
    :heroku_oauth_token,
    :heroku_session_nonce,
    :heroku_user_session,
    :oauth_token,
    :passwd,
    :password_confirmation,
    :password,
    :postgres_session_nonce,
    :"request.cookies.signup-sso-session",
    :secret_token,
    :secret,
    :sudo_oauth_token,
    :super_user_session_secret,
    :user_session_secret,
    :"www-sso-session",
  ]
end
