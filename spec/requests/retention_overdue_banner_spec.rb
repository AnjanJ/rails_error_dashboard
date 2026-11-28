# frozen_string_literal: true

require "rails_helper"

# While retention_days is set and an error has gone unseen for more than
# retention_days plus two days, the retention job isn't running: every
# dashboard page says so, and names the job.
RSpec.describe "Retention overdue banner", type: :request do
  let!(:application) { create(:application) }
  let(:config) { RailsErrorDashboard.configuration }

  before do
    config.authenticate_with = -> { true }
    config.retention_days = 30
  end

  after { RailsErrorDashboard.reset_configuration! }

  def unseen_for(days)
    create(:error_log, application: application, occurred_at: (days + 5).days.ago, last_seen_at: days.days.ago)
  end

  def banner_on(path = "/error_dashboard/errors")
    get path
    expect(response).to have_http_status(:ok)
    response.body.include?('id="retention-overdue-warning"')
  end

  it "shows, naming the job, while an error unseen for 33 days is stored (hardening-1-0-rc2/REQ-26)" do
    unseen_for(33)

    get "/error_dashboard/errors"

    expect(response.body).to include('id="retention-overdue-warning"', "RailsErrorDashboard::RetentionCleanupJob")
  end

  it "shows on the other dashboard pages too (hardening-1-0-rc2/REQ-26)" do
    unseen_for(33)

    expect(banner_on("/error_dashboard")).to be true
    expect(banner_on("/error_dashboard/settings")).to be true
  end

  it "doesn't show for an error unseen for 31 days, inside the two days' grace (hardening-1-0-rc2/REQ-26)" do
    unseen_for(31)

    expect(banner_on).to be false
  end

  it "doesn't show with retention_days nil (hardening-1-0-rc2/REQ-26)" do
    config.retention_days = nil
    unseen_for(400)

    expect(banner_on).to be false
  end

  it "keeps its answer for an hour (hardening-1-0-rc2/REQ-26)" do
    expect(banner_on).to be false
    unseen_for(33)

    expect(banner_on).to be false

    travel 61.minutes do
      expect(banner_on).to be true
    end
  end

  it "goes once the retention job has deleted the errors (hardening-1-0-rc2/REQ-26)" do
    unseen_for(33)
    expect(banner_on).to be true

    RailsErrorDashboard::RetentionCleanupJob.new.perform

    expect(banner_on).to be false
  end

  it "leaves the page working when the check fails (hardening-1-0-rc2/REQ-26)" do
    unseen_for(33)
    allow(RailsErrorDashboard::RetentionCleanupJob).to receive(:expired_scope).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect(banner_on).to be false
  end
end
