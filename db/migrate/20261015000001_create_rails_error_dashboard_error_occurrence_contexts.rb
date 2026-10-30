# frozen_string_literal: true

# The moment-of-failure context of individual occurrences: breadcrumbs, system
# health, local and instance variables, as the error row stores them for its
# latest capture. The error row keeps only the latest; this keeps the last
# config.occurrence_context_limit occurrences per error (default 25).
#
# A side table, not columns on error_occurrences: the co-occurrence queries
# load occurrence rows whole, and these payloads run to several KB.
#
# up/down rather than `change`: the table_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the drop.
class CreateRailsErrorDashboardErrorOccurrenceContexts < ActiveRecord::Migration[7.0]
  def up
    # Guard against the squashed schema migration having already created this
    # table -- without it, every later migration is silently cancelled.
    return if table_exists?(:rails_error_dashboard_error_occurrence_contexts)

    create_table :rails_error_dashboard_error_occurrence_contexts do |t|
      t.bigint :error_occurrence_id, null: false
      # Denormalized from the occurrence, so trimming to the newest N per error
      # and retention's delete-by-error need no join
      t.bigint :error_log_id, null: false
      t.text :breadcrumbs
      t.text :system_health
      t.text :local_variables
      t.text :instance_variables
      t.datetime :created_at, null: false
    end

    # Named explicitly: an auto-generated name would exceed PostgreSQL's
    # 63-character limit and fail during the HOST app's deploy.
    add_index :rails_error_dashboard_error_occurrence_contexts, :error_occurrence_id,
              unique: true, name: "index_red_occurrence_contexts_on_occurrence"
    add_index :rails_error_dashboard_error_occurrence_contexts, :error_log_id,
              name: "index_red_occurrence_contexts_on_error_log"
  end

  def down
    drop_table :rails_error_dashboard_error_occurrence_contexts, if_exists: true
  end
end
