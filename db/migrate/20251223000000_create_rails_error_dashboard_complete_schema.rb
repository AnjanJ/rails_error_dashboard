# frozen_string_literal: true

# Squashed migration for new installations
# This migration creates the complete Rails Error Dashboard schema in one step.
#
# For existing installations, the incremental migrations (20251224-20260106) will run instead.
# Detection: If error_logs table already exists, this migration is skipped.
class CreateRailsErrorDashboardCompleteSchema < ActiveRecord::Migration[7.0]
  def up
    # Skip if this is an existing installation (error_logs table already exists)
    # Existing installations will use incremental migrations instead
    return if table_exists?(:rails_error_dashboard_error_logs)

    # Create applications table
    create_table :rails_error_dashboard_applications do |t|
      t.string :name, limit: 255, null: false
      t.text :description
      t.datetime :created_at
      t.datetime :updated_at
    end
    add_index :rails_error_dashboard_applications, :name, unique: true

    # Create error_logs table with ALL columns from incremental migrations
    create_table :rails_error_dashboard_error_logs do |t|
      # Core error fields (from 20251224000001)
      t.string :error_type, null: false
      t.text :message, null: false
      t.text :backtrace
      t.integer :user_id
      t.text :request_url
      t.text :request_params
      t.text :user_agent
      t.string :ip_address
      t.string :platform
      t.boolean :resolved, null: false, default: false
      t.text :resolution_comment
      t.string :resolution_reference
      t.string :resolved_by_name
      t.datetime :resolved_at
      t.datetime :occurred_at, null: false

      # Enhanced tracking fields (from 20251224081522)
      t.string :error_hash
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.integer :occurrence_count, default: 1, null: false

      # Controller/action context (from 20251224101217)
      t.string :controller_name
      t.string :action_name

      # Enhanced metrics (from 20251225085859)
      t.string :app_version
      t.string :git_sha
      t.integer :priority_score

      # Similarity tracking (from 20251225093603)
      t.float :similarity_score
      t.string :backtrace_signature

      # Workflow fields (from 20251226020000)
      t.string :status, default: "new"
      t.string :assigned_to
      t.datetime :snoozed_until
      t.integer :priority_level, default: 0

      # Application association (from 20260106094233)
      t.integer :application_id, null: false

      t.timestamps
    end

    # Add ALL indexes from incremental migrations
    # Basic indexes (from 20251224000001)
    add_index :rails_error_dashboard_error_logs, :error_type
    add_index :rails_error_dashboard_error_logs, :resolved
    add_index :rails_error_dashboard_error_logs, :user_id
    add_index :rails_error_dashboard_error_logs, :occurred_at
    add_index :rails_error_dashboard_error_logs, :platform

    # Tracking indexes (from 20251224081522)
    add_index :rails_error_dashboard_error_logs, :error_hash
    add_index :rails_error_dashboard_error_logs, :first_seen_at
    add_index :rails_error_dashboard_error_logs, :last_seen_at
    add_index :rails_error_dashboard_error_logs, :occurrence_count

    # Composite indexes for performance (from 20251225071314)
    add_index :rails_error_dashboard_error_logs, [ :error_type, :occurred_at ], name: "index_error_logs_on_error_type_and_occurred_at"
    add_index :rails_error_dashboard_error_logs, [ :resolved, :occurred_at ], name: "index_error_logs_on_resolved_and_occurred_at"
    add_index :rails_error_dashboard_error_logs, [ :platform, :occurred_at ], name: "index_error_logs_on_platform_and_occurred_at"
    add_index :rails_error_dashboard_error_logs, [ :error_hash, :resolved, :occurred_at ], name: "index_error_logs_on_hash_resolved_occurred"
    add_index :rails_error_dashboard_error_logs, [ :controller_name, :action_name, :error_hash ], name: "index_error_logs_on_controller_action_hash"

    # Enhanced metrics indexes (from 20251225085859)
    add_index :rails_error_dashboard_error_logs, :app_version
    add_index :rails_error_dashboard_error_logs, :git_sha
    add_index :rails_error_dashboard_error_logs, :priority_score

    # Similarity tracking indexes (from 20251225093603)
    add_index :rails_error_dashboard_error_logs, :similarity_score
    add_index :rails_error_dashboard_error_logs, :backtrace_signature

    # Application indexes (from 20260106094233, 20251229111223)
    add_index :rails_error_dashboard_error_logs, :application_id
    add_index :rails_error_dashboard_error_logs, [ :application_id, :occurred_at ], name: "index_error_logs_on_app_occurred"
    add_index :rails_error_dashboard_error_logs, [ :application_id, :resolved ], name: "index_error_logs_on_app_resolved"

    # Create error_occurrences table (from 20251225100236)
    create_table :rails_error_dashboard_error_occurrences do |t|
      t.integer :error_log_id, null: false
      t.datetime :occurred_at, null: false
      t.integer :user_id
      t.string :request_id
      t.string :session_id
      t.timestamps
    end
    add_index :rails_error_dashboard_error_occurrences, :error_log_id, name: "index_error_occurrences_on_error_log"
    add_index :rails_error_dashboard_error_occurrences, [ :occurred_at, :error_log_id ], name: "index_error_occurrences_on_time_and_error"
    add_index :rails_error_dashboard_error_occurrences, :user_id, name: "index_error_occurrences_on_user"
    add_index :rails_error_dashboard_error_occurrences, :request_id, name: "index_error_occurrences_on_request"

    # Create cascade_patterns table (from 20251225101920)
    create_table :rails_error_dashboard_cascade_patterns do |t|
      t.integer :parent_error_id, null: false
      t.integer :child_error_id, null: false
      t.integer :frequency, default: 1, null: false
      t.float :avg_delay_seconds
      t.float :cascade_probability
      t.datetime :last_detected_at
      t.timestamps
    end
    add_index :rails_error_dashboard_cascade_patterns, :parent_error_id, name: "index_cascade_patterns_on_parent"
    add_index :rails_error_dashboard_cascade_patterns, :child_error_id, name: "index_cascade_patterns_on_child"
    add_index :rails_error_dashboard_cascade_patterns, [ :parent_error_id, :child_error_id ], unique: true, name: "index_cascade_patterns_on_parent_and_child"
    add_index :rails_error_dashboard_cascade_patterns, :cascade_probability, name: "index_cascade_patterns_on_probability"

    # Create error_baselines table (from 20251225102500)
    create_table :rails_error_dashboard_error_baselines do |t|
      t.string :error_type, null: false
      t.string :platform, null: false
      t.string :baseline_type, null: false
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.integer :count, default: 0, null: false
      t.float :mean
      t.float :std_dev
      t.float :percentile_95
      t.float :percentile_99
      t.integer :sample_size, default: 0, null: false
      t.timestamps
    end
    add_index :rails_error_dashboard_error_baselines, [ :error_type, :platform ], name: "index_error_baselines_on_error_type_and_platform"
    add_index :rails_error_dashboard_error_baselines, :period_end, name: "index_error_baselines_on_period_end"
    add_index :rails_error_dashboard_error_baselines, [ :error_type, :platform, :baseline_type, :period_start ], name: "index_error_baselines_on_type_platform_baseline_period"

    # Create error_comments table (from 20251226020100)
    create_table :rails_error_dashboard_error_comments do |t|
      t.integer :error_log_id, null: false
      t.string :author_name, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :rails_error_dashboard_error_comments, :error_log_id
    add_index :rails_error_dashboard_error_comments, [ :error_log_id, :created_at ], name: "index_error_comments_on_error_and_time"

    # Add foreign keys
    add_foreign_key :rails_error_dashboard_error_logs, :rails_error_dashboard_applications, column: :application_id
    add_foreign_key :rails_error_dashboard_error_occurrences, :rails_error_dashboard_error_logs, column: :error_log_id
    add_foreign_key :rails_error_dashboard_cascade_patterns, :rails_error_dashboard_error_logs, column: :parent_error_id
    add_foreign_key :rails_error_dashboard_cascade_patterns, :rails_error_dashboard_error_logs, column: :child_error_id
    add_foreign_key :rails_error_dashboard_error_comments, :rails_error_dashboard_error_logs, column: :error_log_id
  end

  def down
    drop_table :rails_error_dashboard_error_comments, if_exists: true
    drop_table :rails_error_dashboard_cascade_patterns, if_exists: true
    drop_table :rails_error_dashboard_error_baselines, if_exists: true
    drop_table :rails_error_dashboard_error_occurrences, if_exists: true
    drop_table :rails_error_dashboard_error_logs, if_exists: true
    drop_table :rails_error_dashboard_applications, if_exists: true
  end
end
