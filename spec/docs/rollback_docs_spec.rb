# frozen_string_literal: true

require "rails_helper"

# What can and can't be rolled back, on every page that says so. The Jekyll
# copies under _reference/ are maintained by hand, and they drift.
RSpec.describe "The rollback docs" do
  root = RailsErrorDashboard::Engine.root
  pages = %w[docs/TROUBLESHOOTING.md docs/GLOSSARY.md _reference/troubleshooting.md _reference/glossary.md]
  irreversible = Dir[root.join("db/migrate/*.rb")].select { |file| File.read(file).include?("IrreversibleMigration") }
  versions = irreversible.map { |file| File.basename(file)[/\A\d+/] }

  it "has four irreversible migrations to name (migration-rollback/REQ-8)" do
    expect(versions).to contain_exactly("20260106094256", "20260325000001", "20260909000001", "20260915000001")
  end

  pages.each do |page|
    describe page do
      let(:text) { File.read(root.join(page)) }

      it "names each migration that can't be rolled back (migration-rollback/REQ-8)" do
        expect(text).to include(*versions)
      end

      it "says where db:rollback stops (migration-rollback/REQ-8)" do
        expect(text).to match(/db:rollback.{0,40}stops at.{0,20}20260915000001/m)
      end

      it "says the database decides for the two that depend on it (migration-rollback/REQ-8)" do
        expect(text).to match(/20260325000001.{0,80}MySQL/m).and match(/20260909000001.{0,80}PostgreSQL/m)
      end

      it "says older installs keep copies whose down does nothing (migration-rollback/REQ-8)" do
        expect(text).to match(/before 0\.18\.0.{0,80}old copies/m).and match(/\b33\b/)
      end

      if page.downcase.include?("troubleshooting")
        it "says what a later index does on SQLite (migration-rollback/REQ-1)" do
          expect(text).to match(/SQLite.{0,300}no such column/m)
        end
      end

      it "shows how to remove a leftover table or column by hand (migration-rollback/REQ-8)" do
        expect(text).to include("bin/rails runner", "drop_table", "remove_column")
      end
    end
  end

  it "no longer says rollbacks are simply supported (migration-rollback/REQ-8)" do
    %w[docs/GLOSSARY.md _reference/glossary.md].each do |page|
      expect(File.read(root.join(page))).not_to include("supports database rollbacks")
    end
  end
end
