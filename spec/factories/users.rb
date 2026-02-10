# frozen_string_literal: true

# Simple mock user for testing (no database table needed).
# Supports FactoryBot's create() which calls save! internally.
MockUser = Struct.new(:id, :email, keyword_init: true) do
  def save!
    true
  end
end

FactoryBot.define do
  factory :user, class: MockUser do
    sequence(:id) { |n| n }
    sequence(:email) { |n| "user#{n}@example.com" }
  end
end
