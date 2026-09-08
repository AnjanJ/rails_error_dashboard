# frozen_string_literal: true

require "rails_helper"

# The PostgreSQL-only indexes the query layer relies on, checked against the
# schema this run was built with. On the CI PostgreSQL row that schema comes
# from db/migrate (RED_TEST_SCHEMA=migrations), so these examples see exactly
# what a fresh install gets — the gap this guards against went unnoticed for
# nine months because the squashed first migration omitted these indexes and
# nothing ran on PostgreSQL to notice.
RSpec.describe "PostgreSQL-only indexes", if: ActiveRecord::Base.connection.adapter_name.downcase == "postgresql" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:table_name) { :rails_error_dashboard_error_logs }

  def index_names
    connection.select_values(
      "SELECT indexname FROM pg_indexes WHERE tablename = #{connection.quote(table_name.to_s)}"
    )
  end

  it "has the partial index on unresolved rows" do
    index = connection.indexes(table_name).find { |i| i.name == "index_error_logs_on_occurred_at_unresolved" }

    expect(index).to be_present
    expect(index.columns).to eq([ "occurred_at" ])
    expect(index.where).to eq("(resolved = false)")
  end

  describe "full-text search" do
    # The real search query, stripped to its predicate: no ordering, no
    # resolved filter (unresolved: false), no pagination. With sequential
    # scans disabled the planner can satisfy the predicate only through an
    # index whose expression matches the query's, so the plan names the
    # index the search actually uses — or none.
    def search_plan
      sql = RailsErrorDashboard::Queries::ErrorsList
              .call(search: "payment", unresolved: false)
              .unscope(:order)
              .select(:id)
              .to_sql

      connection.transaction(requires_new: true) do
        connection.execute("SET LOCAL enable_seqscan = off")
        connection.select_values("EXPLAIN #{sql}").join("\n")
      end
    end

    it "is served by index_error_logs_on_searchable_text" do
      expect(index_names).to include("index_error_logs_on_searchable_text")
      expect(search_plan).to include("index_error_logs_on_searchable_text")
    end

    it "does not carry the message-only GIN index" do
      # Its expression (message alone) matches no query the gem runs, so it
      # was only ever write overhead. Replaced by
      # 20260909000001_replace_message_gin_with_searchable_text_index.
      expect(index_names).not_to include("index_error_logs_on_message_gin")
    end
  end
end
