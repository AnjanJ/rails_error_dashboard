# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-11: a row that failed in a batch action was logged
# only through RED's own logger, which is silent by default, and the flash said
# "Failed to mute 1 error" without saying which one or why.
RSpec.describe "Batch failure reporting" do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = config.log_level
    config.log_level = :silent
    example.run
  ensure
    config.log_level = saved
  end

  {
    RailsErrorDashboard::Commands::BatchMuteErrors => { muted_by: "ops" },
    RailsErrorDashboard::Commands::BatchUnmuteErrors => {},
    RailsErrorDashboard::Commands::BatchResolveErrors => {}
  }.each do |command, options|
    it "#{command.name.demodulize} names the failed errors, and logs why, with log_level :silent" do
      good, bad = create_list(:error_log, 2)
      allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:update!).and_wrap_original do |original, *args, **kwargs|
        raise "disk full" if original.receiver.id == bad.id

        original.call(*args, **kwargs)
      end
      allow(Rails.logger).to receive(:warn)

      result = command.call([ good.id, bad.id ], **options)

      expect(result[:failures]).to eq(bad.id => "RuntimeError: disk full")
      expect(result[:errors].join).to include("##{bad.id}")
      expect(Rails.logger).to have_received(:warn).with(/error #{bad.id}: RuntimeError: disk full/)
    end
  end
end
