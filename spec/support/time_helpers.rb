# frozen_string_literal: true

module TimeHelpers
  def freeze_time(&block)
    travel_to(Time.current, &block)
  end
end

RSpec.configure do |config|
  config.include TimeHelpers
  config.include ActiveSupport::Testing::TimeHelpers
end
