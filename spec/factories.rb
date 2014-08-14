FactoryGirl.define do
  to_create { |instance| instance.save }

  sequence :log_input_url do |i|
    "https://token:t.logplex-token-#{i}@example.com/logs"
  end

  sequence :from_url do |i|
    "postgres://example.com/db-#{i}"
  end

  sequence :to_url do |i|
    "https://bucket.s3.amazonaws.com/key-#{i}"
  end

  sequence :timezone do |i|
    zones = %w(America/Los_Angeles America/New_York Europe/Paris Asia/Hong_Kong)
    zones.at(i % zones.length)
  end

  factory :transfer, class: Transferatu::Transfer do
    from_type "pg_dump"
    from_url
    to_type "gof3r"
    to_url
    group
  end

  factory :group, class: Transferatu::Group do
    user
    sequence(:name) { |i| "group-#{i}" }
    log_input_url
  end

  factory :user, class: Transferatu::User do
    sequence(:name)          { |i| "user-#{i}" }
    sequence(:token)         { |i| SecureRandom.base64(32) }
    sequence(:password_hash) { |i| "bogus-hash-#{i}" } # don't bother with bcrypt unless we need it
  end

  factory :schedule, class: Transferatu::Schedule do
    group
    sequence(:name)         { |i| "schedule-#{i}" }
    sequence(:callback_url) { |i| "https://example.com/transferatu/schedules/group-#{i}" }
    sequence(:hour)         { |i| i % 24 }
    # an arbitrary but not random set of days to run
    sequence(:dows)         { |i| (0..6).reject { |j| i % (j + 1) < 1 }.each_slice(4).first }
    timezone
  end
end
