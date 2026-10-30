# frozen_string_literal: true

# up/down rather than `change`: the table_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the drop.
class CreateRailsErrorDashboardDiagnosticDumps < ActiveRecord::Migration[7.0]
  def up
    # Guard against the squashed schema migration having already created this
    # table — without it, every later migration is silently cancelled.
    return if table_exists?(:rails_error_dashboard_diagnostic_dumps)

    create_table :rails_error_dashboard_diagnostic_dumps do |t|
      t.references :application, null: false,
        foreign_key: { to_table: :rails_error_dashboard_applications }
      t.text :dump_data, null: false
      t.string :note
      t.datetime :captured_at, null: false
      t.timestamps
    end

    add_index :rails_error_dashboard_diagnostic_dumps, :captured_at,
              name: "index_diagnostic_dumps_on_captured_at"
  end

  def down
    drop_table :rails_error_dashboard_diagnostic_dumps, if_exists: true
  end
end
