# frozen_string_literal: true

class CreateRailsErrorDashboardSwallowedExceptions < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_error_dashboard_swallowed_exceptions do |t|
      t.string   :exception_class,  null: false, limit: 250
      t.string   :raise_location,   null: false, limit: 250
      t.string   :rescue_location,  limit: 250
      t.datetime :period_hour,      null: false
      t.integer  :raise_count,      null: false, default: 0
      t.integer  :rescue_count,     null: false, default: 0
      t.datetime :last_seen_at
      t.bigint   :application_id
      t.timestamps
    end

    add_index :rails_error_dashboard_swallowed_exceptions,
              [ :exception_class, :period_hour ],
              name: "index_swallowed_exceptions_on_class_and_hour"

    add_index :rails_error_dashboard_swallowed_exceptions,
              :period_hour,
              name: "index_swallowed_exceptions_on_period_hour"

    add_index :rails_error_dashboard_swallowed_exceptions,
              [ :application_id, :period_hour ],
              name: "index_swallowed_exceptions_on_app_and_hour"

    add_index :rails_error_dashboard_swallowed_exceptions,
              [ :exception_class, :raise_location, :rescue_location, :period_hour, :application_id ],
              unique: true,
              name: "index_swallowed_exceptions_upsert_key"
  end
end
