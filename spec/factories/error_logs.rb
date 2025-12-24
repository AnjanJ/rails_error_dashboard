# frozen_string_literal: true

FactoryBot.define do
  factory :error_log, class: 'RailsErrorDashboard::ErrorLog' do
    error_type { [ 'ActiveRecord::RecordNotFound', 'ArgumentError', 'NoMethodError', 'TypeError' ].sample }
    message { Faker::Lorem.sentence }
    backtrace { "#{Faker::File.file_name}:#{Faker::Number.between(from: 1, to: 100)}:in `#{Faker::Hacker.verb}'\n" * 5 }
    user_id { nil }
    request_url { Faker::Internet.url(path: "/#{Faker::Internet.slug}") }
    request_params { { controller: 'users', action: 'show', id: rand(1..100) }.to_json }
    user_agent { Faker::Internet.user_agent }
    ip_address { Faker::Internet.ip_v4_address }
    environment { [ 'development', 'staging', 'production' ].sample }
    platform { [ 'iOS', 'Android', 'API', 'Web' ].sample }
    resolved { false }
    occurred_at { Time.current }

    trait :resolved do
      resolved { true }
      resolved_by_name { Faker::Name.name }
      resolved_at { Time.current }
      resolution_comment { Faker::Lorem.paragraph }
      resolution_reference { "PR-#{Faker::Number.number(digits: 3)}" }
    end

    trait :ios do
      platform { 'iOS' }
      user_agent { 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)' }
    end

    trait :android do
      platform { 'Android' }
      user_agent { 'Mozilla/5.0 (Linux; Android 13)' }
    end

    trait :api do
      platform { 'API' }
      user_agent { 'Rails Application' }
    end

    trait :production do
      environment { 'production' }
    end

    trait :with_user do
      user_id { rand(1..100) }
    end
  end
end
