# frozen_string_literal: true

FactoryBot.define do
  factory :application, class: 'RailsErrorDashboard::Application' do
    sequence(:name) { |n| "Application_#{n}" }
    description { "Test application for specs" }
  end
end
