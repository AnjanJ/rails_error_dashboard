# frozen_string_literal: true

class CreateRailsErrorDashboardRackAttackEvents < ActiveRecord::Migration[7.0]
  def change
    # Guard against the squashed schema migration having already created this
    # table — without it, every later migration is silently cancelled.
    return if table_exists?(:rails_error_dashboard_rack_attack_events)

    create_table :rails_error_dashboard_rack_attack_events do |t|
      t.string   :rule,          null: false, limit: 250
      t.string   :match_type,    null: false, limit: 50
      # discriminator and path are capped at 191 (not 250) to keep the unique
      # upsert index within MySQL's 3072-byte utf8mb4 limit. Budget:
      # 250+50+191+191 chars * 4 bytes + 2 length-prefix each = 2736 bytes.
      # See issue #96 — the swallowed_exceptions index blew this limit at 5042.
      t.string   :discriminator, limit: 191
      t.string   :path,          limit: 191
      t.string   :http_method,   limit: 10
      t.datetime :period_hour,   null: false
      t.integer  :event_count,   null: false, default: 0
      t.datetime :last_seen_at
      t.bigint   :application_id
      t.timestamps
    end

    add_index :rails_error_dashboard_rack_attack_events,
              :period_hour,
              name: "index_rack_attack_events_on_period_hour"

    add_index :rails_error_dashboard_rack_attack_events,
              [ :application_id, :period_hour ],
              name: "index_rack_attack_events_on_app_and_hour"

    add_index :rails_error_dashboard_rack_attack_events,
              [ :rule, :period_hour ],
              name: "index_rack_attack_events_on_rule_and_hour"

    # http_method is intentionally NOT part of the upsert key — it would push
    # the index over the MySQL byte limit and adds no aggregation value.
    add_index :rails_error_dashboard_rack_attack_events,
              [ :rule, :match_type, :discriminator, :path, :period_hour, :application_id ],
              unique: true,
              name: "index_rack_attack_events_upsert_key"
  end
end
