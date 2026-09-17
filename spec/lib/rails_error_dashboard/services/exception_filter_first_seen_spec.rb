# frozen_string_literal: true

require "rails_helper"

# Sampling is a dice roll per event, taken before anything is known about the
# error. At a rate of 0.01 an error that happens three times is, more often
# than not, never recorded at all. Sampling is for VOLUME; it must not hide
# the existence of an error.
RSpec.describe "ExceptionFilter first-seen admission under sampling" do
  let(:filter) { RailsErrorDashboard::Services::ExceptionFilter }
  let(:config) { RailsErrorDashboard.configuration }

  before do
    filter.reset_seen!
    config.sampling_rate = 0.0001
    allow(filter).to receive(:rand).and_return(0.99) # the dice always say "drop"
  end

  after do
    filter.reset_seen!
    RailsErrorDashboard.reset_configuration!
  end

  def error(klass, frame, message: "boom")
    e = klass.new(message)
    e.set_backtrace([ "/gems/activesupport-8.1/lib/x.rb:1:in 'y'", frame ])
    e
  end

  let(:frame_x) { "#{Rails.root}/app/models/widget.rb:10:in 'explode'" }
  let(:frame_y) { "#{Rails.root}/app/models/gadget.rb:22:in 'implode'" }

  it "admits the first event of an error and samples the second" do
    expect(filter.sampled_out?(error(ArgumentError, frame_x))).to be false
    expect(filter.sampled_out?(error(ArgumentError, frame_x))).to be true
  end

  it "treats a different class at the same frame as a different error" do
    filter.sampled_out?(error(ArgumentError, frame_x))

    expect(filter.sampled_out?(error(TypeError, frame_x))).to be false
  end

  it "treats the same class at a different application frame as a different error" do
    filter.sampled_out?(error(ArgumentError, frame_x))

    expect(filter.sampled_out?(error(ArgumentError, frame_y))).to be false
  end

  it "keys on the first APPLICATION frame, not the gem frame above it" do
    filter.sampled_out?(error(ArgumentError, frame_x))
    same_app_frame_other_gem = ArgumentError.new("boom")
    same_app_frame_other_gem.set_backtrace([ "/gems/rack-3.1/lib/z.rb:9:in 'call'", frame_x ])

    expect(filter.sampled_out?(same_app_frame_other_gem)).to be true
  end

  it "does not let the message create new firsts" do
    filter.sampled_out?(error(ArgumentError, frame_x, message: "user 1"))

    expect(filter.sampled_out?(error(ArgumentError, frame_x, message: "user 2"))).to be true
  end

  it "handles an exception that was never raised (no backtrace)" do
    expect(filter.sampled_out?(ArgumentError.new("no trace"))).to be false
    expect(filter.sampled_out?(ArgumentError.new("no trace"))).to be true
  end

  it "stays bounded however many distinct errors pass through" do
    3_000.times { |i| filter.sampled_out?(error(ArgumentError, "#{Rails.root}/app/models/m#{i}.rb:1:in 'x'")) }

    expect(filter.seen_size).to be <= filter::MAX_SEEN
    expect(filter::MAX_SEEN).to eq(1_000)
  end

  it "still rolls the dice normally once an error has been seen" do
    filter.sampled_out?(error(ArgumentError, frame_x))
    allow(filter).to receive(:rand).and_return(0.00001)

    expect(filter.sampled_out?(error(ArgumentError, frame_x))).to be false
  end

  it "leaves critical exceptions and a rate of 1.0 exactly as they were" do
    expect(filter.sampled_out?(error(SecurityError, frame_x))).to be false
    expect(filter.sampled_out?(error(SecurityError, frame_x))).to be false

    config.sampling_rate = 1.0
    expect(filter.sampled_out?(error(ArgumentError, frame_y))).to be false
    expect(filter.seen_size).to eq(0) # nothing to remember when nothing is sampled
  end

  # 0.0 is the documented "record nothing but critical errors" switch.
  it "keeps a rate of 0.0 as a hard off switch" do
    config.sampling_rate = 0.0

    expect(filter.sampled_out?(error(ArgumentError, frame_x))).to be true
  end

  it "admits when the seen-set itself fails" do
    allow(filter).to receive(:seen_key).and_raise(RuntimeError, "broken")

    expect(filter.sampled_out?(error(ArgumentError, frame_x))).to be false
  end

  it "is safe under concurrent first sightings: exactly one first per error" do
    results = Array.new(8) { Thread.new { filter.sampled_out?(error(ArgumentError, frame_x)) } }.map(&:value)

    expect(results.count(false)).to eq(1)
  end
end
