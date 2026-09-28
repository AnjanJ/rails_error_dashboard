# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::UninstallPlan do
  describe ".call" do
    let(:plan) { described_class.call(red_connection) }
    let(:tables) { plan.map { |entry| entry[:table] } }

    it "lists every RED table on the error database, and nothing else" do
      expect(tables).to match_array(red_tables)
      expect(tables).to include(
        "rails_error_dashboard_error_logs", "rails_error_dashboard_applications",
        "rails_error_dashboard_rack_attack_events", "rails_error_dashboard_diagnostic_dumps"
      )
    end

    it "puts every table that holds a foreign key before the table it references" do
      red_tables.each do |table|
        red_connection.foreign_keys(table).each do |fk|
          next unless tables.include?(fk.to_table)

          expect(tables.index(table)).to be < tables.index(fk.to_table),
            "#{table} references #{fk.to_table} but is dropped after it"
        end
      end
    end

    it "counts the rows in each table" do
      create(:error_log)

      entry = plan.find { |e| e[:table] == "rails_error_dashboard_error_logs" }

      expect(entry[:rows]).to eq(1)
    end
  end

  describe ".order" do
    it "drops referencing tables before the tables they reference" do
      order = described_class.order(
        "logs" => [ "apps" ], "comments" => [ "logs" ], "apps" => [], "dumps" => [ "apps" ]
      )

      expect(order.index("comments")).to be < order.index("logs")
      expect(order.index("logs")).to be < order.index("apps")
      expect(order.index("dumps")).to be < order.index("apps")
    end

    it "ignores a table that references itself" do
      expect(described_class.order("tree" => [ "tree" ])).to eq([ "tree" ])
    end

    it "raises a clear error on a foreign-key cycle instead of looping" do
      expect { described_class.order("a" => [ "b" ], "b" => [ "a" ]) }
        .to raise_error(described_class::CycleError, /a, b/)
    end
  end
end
