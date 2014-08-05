namespace :users do
  task :create, :name do |t, args|
    require "bundler"
    Bundler.require
    require_relative "../initializer"
    require "securerandom"

    password = SecureRandom.base64(128)
    if password.empty?
      raise StandardError, "Could not generate password"
    end
    token=`dd if=/dev/urandom bs=32 count=1 2>/dev/null | openssl base64`.strip
    if token.empty?
      raise StandardError, "Could not generate token"
    end
    callback_password = SecureRandom.base64(128)
    if callback_password.empty?
      raise StandardError, "Could not generate token"
    end
    Transferatu::User.create(name: args.name,
                             password: password,
                             token: token,
                             callback_password: callback_password)
    puts <<-EOF
Created user #{args.name} with
  password: #{password}
  token: #{token}
  callback password: #{callback_password}
EOF
  end
end
