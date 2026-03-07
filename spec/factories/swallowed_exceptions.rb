# frozen_string_literal: true

FactoryBot.define do
  factory :swallowed_exception, class: "RailsErrorDashboard::SwallowedException" do
    exception_class { "Stripe::CardError" }
    raise_location { "app/services/payment_service.rb:42" }
    rescue_location { "app/services/payment_service.rb:45" }
    period_hour { Time.current.beginning_of_hour }
    raise_count { 100 }
    rescue_count { 95 }
    last_seen_at { Time.current }
    application

    trait :fully_swallowed do
      raise_count { 100 }
      rescue_count { 100 }
    end

    trait :partially_swallowed do
      raise_count { 100 }
      rescue_count { 50 }
    end

    trait :not_swallowed do
      raise_count { 100 }
      rescue_count { 10 }
    end
  end
end
