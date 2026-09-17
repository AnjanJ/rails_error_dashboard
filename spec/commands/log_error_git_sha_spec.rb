# frozen_string_literal: true

require "rails_helper"

# With no configured SHA and no platform ENV variable, every single capture
# used to run `git rev-parse` in a subprocess: a fork + exec in the request
# thread, per error. SystemHealthSnapshot's own rule is "no fork/subprocess
# ever"; the capture path now honours it.
RSpec.describe "LogError git SHA resolution" do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = %w[GIT_SHA HEROKU_SLUG_COMMIT RENDER_GIT_COMMIT].to_h { |k| [ k, ENV.delete(k) ] }
    example.run
  ensure
    saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
    RailsErrorDashboard.reset_detected_git_sha!
    RailsErrorDashboard.reset_configuration!
  end

  before do
    config.async_logging = false
    config.git_sha = nil
    RailsErrorDashboard.reset_detected_git_sha!
  end

  def capture(i)
    error = StandardError.new("sha #{i}")
    error.set_backtrace([ "#{Rails.root}/app/models/sha_#{i}.rb:#{i + 1}:in 'x'" ])
    RailsErrorDashboard::Commands::LogError.call(error, {})
  end

  it "spawns no subprocess, however many errors are captured" do
    allow_any_instance_of(RailsErrorDashboard::Commands::LogError).to receive(:`) do |*|
      raise "LogError shelled out"
    end
    expect(Kernel).not_to receive(:system)

    rows = Array.new(50) { |i| capture(i) }

    expect(rows.compact.size).to eq(50)
    expect(RailsErrorDashboard::Commands::LogError.private_instance_methods).not_to include(:detect_git_sha_from_command)
  end

  it "reads the repository once per process, not once per error" do
    allow(RailsErrorDashboard::Services::GitHeadReader).to receive(:call).and_return("abc1234")

    rows = Array.new(10) { |i| capture(i) }

    expect(RailsErrorDashboard::Services::GitHeadReader).to have_received(:call).once
    expect(rows.map(&:git_sha).uniq).to eq([ "abc1234" ])
  end

  it "memoises a nil result too (no repository: do not look again for every error)" do
    allow(RailsErrorDashboard::Services::GitHeadReader).to receive(:call).and_return(nil)

    5.times { |i| capture(i) }

    expect(RailsErrorDashboard::Services::GitHeadReader).to have_received(:call).once
  end

  it "still prefers the configured SHA, then the platform ENV variables" do
    allow(RailsErrorDashboard::Services::GitHeadReader).to receive(:call).and_return("fromgit")
    ENV["GIT_SHA"] = "fromenv"
    expect(capture(1).git_sha).to eq("fromenv")

    config.git_sha = "fromconfig"
    expect(capture(2).git_sha).to eq("fromconfig")
  end

  it "never raises into the capture path when detection fails" do
    allow(RailsErrorDashboard::Services::GitHeadReader).to receive(:call).and_raise(Errno::EACCES)

    expect(capture(1)).to be_persisted
    expect(RailsErrorDashboard.detected_git_sha).to be_nil
  end
end
