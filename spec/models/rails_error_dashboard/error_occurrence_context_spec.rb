# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ErrorOccurrenceContext do
  let(:error) { create(:error_log) }
  let(:occurrence) { create(:error_occurrence, error_log: error) }

  def context_for(occurrence)
    described_class.create!(error_occurrence: occurrence, error_log: occurrence.error_log, breadcrumbs: "[]")
  end

  it "lives in the error database" do
    expect(described_class.ancestors).to include(RailsErrorDashboard::ErrorLogsRecord)
  end

  it "belongs to its occurrence and its error" do
    context = context_for(occurrence)

    expect(occurrence.reload.context).to eq(context)
    expect(error.occurrence_contexts).to eq([ context ])
  end

  # occurrence-context-history/REQ-5
  it "is deleted with its error" do
    context_for(occurrence)

    expect { error.destroy }.to change(described_class, :count).by(-1)
  end

  # occurrence-context-history/REQ-5
  it "is deleted with its occurrence" do
    context_for(occurrence)

    expect { occurrence.destroy }.to change(described_class, :count).by(-1)
  end
end
