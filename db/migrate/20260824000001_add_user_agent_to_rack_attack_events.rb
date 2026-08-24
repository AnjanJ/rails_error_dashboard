# frozen_string_literal: true

class AddUserAgentToRackAttackEvents < ActiveRecord::Migration[7.0]
  def change
    # Guard against the squashed schema migration having already added this
    # column — without it, every later migration is silently cancelled.
    return if column_exists?(:rails_error_dashboard_rack_attack_events, :user_agent)

    # Capped at 191 to match the other free-text columns on this table.
    #
    # Deliberately NOT added to index_rack_attack_events_upsert_key. That index
    # is already budgeted at 250+50+191+191 chars = 2736 bytes against MySQL's
    # 3072-byte utf8mb4 limit (see the create migration); a fourth 191-char
    # column would blow it. User agents are also extremely high cardinality, so
    # indexing them would fragment the hourly buckets this table exists to
    # aggregate. It is stored first-write-wins per bucket, like http_method.
    add_column :rails_error_dashboard_rack_attack_events, :user_agent, :string, limit: 191
  end
end
