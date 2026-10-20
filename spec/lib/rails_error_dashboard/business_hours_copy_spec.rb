# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-1/REQ-10: the business-hours pattern's description said
# "9am-5pm" (and "9–17 Uhr", "9時〜17時", …), but the detector counts the hour
# buckets 9 to 17, so its hours run to 17:59.
RSpec.describe "Business-hours pattern copy" do
  # The hours of day the detector counts as business hours, found by asking it:
  # peaks at an hour plus two known business hours make a business-hours
  # pattern only when that hour counts too.
  counted_hours = (0..23).select do |hour|
    peaks = [ hour ] + ([ 11, 12, 13 ] - [ hour ]).first(2)
    RailsErrorDashboard::Services::PatternDetector.determine_pattern_type(peaks.to_h { |h| [ h, 10 ] }, {}) == :business_hours
  end
  stated_hours = "#{counted_hours.min}:00–#{counted_hours.max}:59"

  it "reads one unbroken range from the detector" do
    expect(counted_hours).to eq((counted_hours.min..counted_hours.max).to_a)
    expect(stated_hours).to eq("9:00–17:59")
  end

  Dir[RailsErrorDashboard::Engine.root.join("config/locales/*.yml")].sort.each do |path|
    locale = File.basename(path, ".yml")

    it "audit-fixes-0-16-1/REQ-10 states #{stated_hours} in #{locale}" do
      description = YAML.load_file(path).dig(locale, "red", "errors", "patterns", "types", "business_hours", "description")

      expect(description).to include(stated_hours)
    end
  end
end
