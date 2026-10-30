# frozen_string_literal: true

require "rails_helper"
require "prism"

# A change can't be reversed if it asks whether something exists. On revert the
# object is there, so the guard skips the very call Rails needed to record, and
# Rails prints "reverted" having dropped nothing. up and down are the fix: see
# 20261015000002_add_capture_source_to_error_occurrences_and_error_logs.rb.
RSpec.describe "No migration guards its change", type: :migration do
  def nodes(node)
    [ node, *node.compact_child_nodes.flat_map { |child| nodes(child) } ]
  end

  def guarded_change?(source)
    changes = nodes(Prism.parse(source).value).grep(Prism::DefNode).select { |definition| definition.name == :change }

    changes.any? do |change|
      nodes(change).grep(Prism::CallNode).any? { |call| call.name.end_with?("_exists?") }
    end
  end

  it "finds none in db/migrate (migration-rollback/REQ-7)" do
    guarded = Dir[RailsErrorDashboard::Engine.root.join("db/migrate/*.rb")].select do |file|
      guarded_change?(File.read(file))
    end

    expect(guarded.map { |file| File.basename(file) }).to be_empty
  end

  it "catches an early return, the form the issue reported (migration-rollback/REQ-7)" do
    expect(guarded_change?(<<~RUBY)).to be(true)
      class CreateThings < ActiveRecord::Migration[7.0]
        def change
          return if table_exists?(:things)

          create_table(:things) { |t| t.string :name }
        end
      end
    RUBY
  end

  it "catches a modifier, the form the issue's list missed (migration-rollback/REQ-7)" do
    expect(guarded_change?(<<~RUBY)).to be(true)
      class AddNameToThings < ActiveRecord::Migration[7.0]
        def change
          add_column :things, :name, :string unless column_exists?(:things, :name)
        end
      end
    RUBY
  end

  it "catches a block, which is a modifier written long (migration-rollback/REQ-7)" do
    expect(guarded_change?(<<~RUBY)).to be(true)
      class AddNameToThings < ActiveRecord::Migration[7.0]
        def change
          unless column_exists?(:things, :name)
            add_column :things, :name, :string
          end
        end
      end
    RUBY
  end

  it "leaves a guarded up alone, and a change that asks nothing (migration-rollback/REQ-7)" do
    expect(guarded_change?(<<~RUBY)).to be(false)
      class AddNameToThings < ActiveRecord::Migration[7.0]
        def change
          add_column :things, :name, :string
        end
      end

      class AddColorToThings < ActiveRecord::Migration[7.0]
        def up
          add_column :things, :color, :string unless column_exists?(:things, :color)
        end
      end
    RUBY
  end
end
