# frozen_string_literal: true

# What's been reported is process-wide, so without this one example's warning
# hides the next one's, in an order that depends on the seed.
RSpec.configure do |config|
  config.after { RailsErrorDashboard::Deprecation.reset! }
end
