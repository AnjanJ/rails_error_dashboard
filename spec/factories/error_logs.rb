# frozen_string_literal: true

FactoryBot.define do
  factory :error_log, class: 'RailsErrorDashboard::ErrorLog' do
    association :application
    error_type { 'StandardError' }
    message { Faker::Lorem.sentence }
    # A REAL Ruby frame, unique per row.
    #
    # The old default used Faker::File.file_name, which produces paths like
    # "turkey_whole/nihil.mp4" -- ErrorNormalizer#extract_file_and_method only
    # matches /\.rb:\d+/, so every such frame parsed to nil and the backtrace
    # contributed NOTHING to error_hash. Two factory rows sharing an
    # error_type and an explicit message therefore shared a fingerprint, and
    # since 20260915000001 a second unresolved row with that identity in the
    # same window is a unique-index violation.
    #
    # Sequencing the file name gives every factory row its own fingerprint by
    # default, which is what a fixture almost always wants. Specs that mean to
    # group rows still do so by passing the same explicit backtrace (51 call
    # sites already do). Five lines, to keep the shape callers assert on.
    sequence(:backtrace) { |n| "/app/models/fixture_#{n}.rb:#{n % 100}:in `call'\n" * 5 }
    user_id { nil }
    request_url { Faker::Internet.url(path: "/#{Faker::Internet.slug}") }
    request_params { { controller: 'users', action: 'show', id: rand(1..100) }.to_json }
    user_agent { Faker::Internet.user_agent }
    ip_address { Faker::Internet.ip_v4_address }
    platform { 'Web' }
    resolved { false }
    occurred_at { Time.current }
    # A freshly captured group was last seen when it occurred. Without this the
    # model stamps last_seen_at with "now", so a row back-dated through
    # occurred_at would look like an error that is still happening today.
    first_seen_at { occurred_at }
    last_seen_at { occurred_at }

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
