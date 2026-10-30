# frozen_string_literal: true

# up/down rather than `change`: the table_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the drop.
class CreateErrorComments < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already created this table
    return if table_exists?(:rails_error_dashboard_error_comments)

    create_table :rails_error_dashboard_error_comments do |t|
      t.references :error_log,
                   null: false,
                   foreign_key: { to_table: :rails_error_dashboard_error_logs }
      t.string :author_name, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :rails_error_dashboard_error_comments, [ :error_log_id, :created_at ],
              name: 'index_error_comments_on_error_and_time'
  end

  def down
    drop_table :rails_error_dashboard_error_comments, if_exists: true
  end
end
