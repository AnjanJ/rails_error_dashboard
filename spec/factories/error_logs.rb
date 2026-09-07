# frozen_string_literal: true

FactoryBot.define do
  factory :error_log, class: 'RailsErrorDashboard::ErrorLog' do
    association :application
    error_type { 'StandardError' }
    message { Faker::Lorem.sentence }
    backtrace { "#{Faker::File.file_name}:#{Faker::Number.between(from: 1, to: 100)}:in `#{Faker::Hacker.verb}'\n" * 5 }
    user_id { nil }
    request_url { Faker::Internet.url(path: "/#{Faker::Internet.slug}") }
    request_params { { controller: 'users', action: 'show', id: rand(1..100) }.to_json }
    user_agent { Faker::Internet.user_agent }
    ip_address { Faker::Internet.ip_v4_address }
    platform { 'Web' }
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

    trait :with_user do
      user_id { rand(1..100) }
    end

    trait :reopened do
      resolved { false }
      reopened_at { Time.current }
    end

    # A versioned capture: the group row plus the occurrence that carries the
    # release it happened under, which is what LogError writes and what
    # ReleaseTimeline counts.
    trait :with_version do
      app_version { "1.0.0" }
      git_sha { SecureRandom.hex(20) }

      after(:create) do |log|
        create(:error_occurrence, error_log: log, occurred_at: log.occurred_at,
                                  app_version: log.app_version, git_sha: log.git_sha)
      end
    end

    trait :with_backtrace do
      backtrace { "app/models/user.rb:10:in `save'\napp/controllers/users_controller.rb:20:in `create'\napp/services/user_service.rb:5:in `process'" }
    end
  end
end
