# frozen_string_literal: true

require "rails_helper"

# The database-enforced identity of an unresolved error group.
#
# Before 20260915000001 nothing stopped two connections that both missed the
# unresolved lookup for one fingerprint from both inserting: two rows, each
# occurrence_count 1, splitting counts and workflow at the moment a new fault
# fans out. FindOrIncrementError always carried a RecordNotUnique retry branch
# for exactly this, but with no unique constraint it could never fire.
#
# MySQL has no partial indexes, so the index is not created there and these
# examples do not apply.
RSpec.describe "error group identity index", type: :migration do
  # DDL + a deliberate constraint violation, so no transactional wrapper.
  self.use_transactional_tests = false

  let(:connection) { RailsErrorDashboard::ErrorLog.connection }
  let(:table) { RailsErrorDashboard::ErrorLog.table_name }

  def mysql?
    connection.adapter_name.downcase.match?(/mysql|trilogy/)
  end

  def index
    connection.indexes(table).find { |i| i.name == "index_error_logs_on_group_identity" }
  end

  let!(:application) { RailsErrorDashboard::Application.find_or_create_by_name("Group identity spec") }

  after do
    RailsErrorDashboard::ErrorLog.where(error_hash: %w[gi-hash gi-hash-2]).delete_all
  end

  def insert_group(environment:, resolved: false, error_hash: "gi-hash", occurred_at: Time.current)
    RailsErrorDashboard::ErrorLog.create!(
      application_id: application.id,
      error_type: "StandardError",
      message: "group identity",
      error_hash: error_hash,
      environment: environment,
      resolved: resolved,
      status: resolved ? "resolved" : "new",
      occurrence_count: 1,
      occurred_at: occurred_at,
      last_seen_at: occurred_at
    )
  end

  it "exists as a unique partial index over the group identity" do
    skip "MySQL has no partial indexes" if mysql?

    expect(index).to be_present
    expect(index.unique).to be true
    # An expression, not plain columns: a plain partial unique index would not
    # constrain legacy NULL rows, because in SQL NULL != NULL. Both nullable
    # members of the identity are wrapped.
    expect(Array(index.columns).join).to include("COALESCE(environment")
    expect(Array(index.columns).join).to include("COALESCE(group_window")
    expect(index.where).to match(/resolved = (false|0)/)
  end

  it "rejects a second unresolved row for the same application, hash and environment" do
    skip "MySQL has no partial indexes" if mysql?

    insert_group(environment: "production")

    expect { insert_group(environment: "production") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  # The hole a plain partial unique index leaves: legacy rows written before
  # the environment column existed carry NULL, and in SQL every NULL differs
  # from every other, so duplicates slip straight through.
  it "rejects a second unresolved row when both environments are NULL" do
    skip "MySQL has no partial indexes" if mysql?

    insert_group(environment: nil)

    expect { insert_group(environment: nil) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "still allows the same error in two different environments" do
    skip "MySQL has no partial indexes" if mysql?

    insert_group(environment: "production")

    expect { insert_group(environment: "staging") }.not_to raise_error
  end

  # Reopen semantics: a resolved row and its unresolved successor coexist, and
  # several resolved rows for one fingerprint are ordinary history.
  # group_window is what keeps this index from forbidding intended behaviour:
  # RED deliberately opens a NEW unresolved group once the previous one ages
  # out of its 24 h window. Two racing creates are milliseconds apart and share
  # a bucket; a create a day later does not.
  it "allows a second unresolved group in a later window" do
    skip "MySQL has no partial indexes" if mysql?

    insert_group(environment: "production", occurred_at: 3.days.ago)

    expect { insert_group(environment: "production", occurred_at: Time.current) }
      .not_to raise_error
  end

  it "stamps the window from occurred_at and never rewrites it" do
    row = insert_group(environment: "production", occurred_at: Time.current)
    stamped = row.group_window

    expect(stamped).to eq(row.occurred_at.utc.strftime("%Y-%m-%d"))

    # An increment refreshes last_seen_at; the identity bucket must not move,
    # or the row would migrate between index slots under a live constraint.
    row.update!(occurrence_count: 2, last_seen_at: Time.current)
    expect(row.reload.group_window).to eq(stamped)
  end

  it "still allows any number of resolved rows for one fingerprint" do
    skip "MySQL has no partial indexes" if mysql?

    insert_group(environment: "production", resolved: true)
    insert_group(environment: "production", resolved: true)

    expect { insert_group(environment: "production", resolved: false) }.not_to raise_error
  end
end
