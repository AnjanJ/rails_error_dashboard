# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_01_06_094318) do
  create_table "rails_error_dashboard_applications", force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.text "description"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index [ "name" ], name: "index_rails_error_dashboard_applications_on_name", unique: true
  end

  create_table "rails_error_dashboard_cascade_patterns", force: :cascade do |t|
    t.integer "parent_error_id", null: false
    t.integer "child_error_id", null: false
    t.integer "frequency", default: 1, null: false
    t.float "avg_delay_seconds"
    t.float "cascade_probability"
    t.datetime "last_detected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "cascade_probability" ], name: "index_cascade_patterns_on_probability"
    t.index [ "child_error_id" ], name: "index_cascade_patterns_on_child"
    t.index [ "parent_error_id", "child_error_id" ], name: "index_cascade_patterns_on_parent_and_child", unique: true
    t.index [ "parent_error_id" ], name: "index_cascade_patterns_on_parent"
  end

  create_table "rails_error_dashboard_error_baselines", force: :cascade do |t|
    t.string "error_type", null: false
    t.string "platform", null: false
    t.string "baseline_type", null: false
    t.datetime "period_start", null: false
    t.datetime "period_end", null: false
    t.integer "count", default: 0, null: false
    t.float "mean"
    t.float "std_dev"
    t.float "percentile_95"
    t.float "percentile_99"
    t.integer "sample_size", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "error_type", "platform", "baseline_type", "period_start" ], name: "index_error_baselines_on_type_platform_baseline_period"
    t.index [ "error_type", "platform" ], name: "index_error_baselines_on_error_type_and_platform"
    t.index [ "period_end" ], name: "index_error_baselines_on_period_end"
  end

  create_table "rails_error_dashboard_error_comments", force: :cascade do |t|
    t.integer "error_log_id", null: false
    t.string "author_name", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "error_log_id", "created_at" ], name: "index_error_comments_on_error_and_time"
    t.index [ "error_log_id" ], name: "index_rails_error_dashboard_error_comments_on_error_log_id"
  end

  create_table "rails_error_dashboard_error_logs", force: :cascade do |t|
    t.string "error_type", null: false
    t.text "message", null: false
    t.text "backtrace"
    t.integer "user_id"
    t.text "request_url"
    t.text "request_params"
    t.text "user_agent"
    t.string "ip_address"
    t.string "platform"
    t.boolean "resolved", null: false
    t.text "resolution_comment"
    t.string "resolution_reference"
    t.string "resolved_by_name"
    t.datetime "resolved_at"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "error_hash"
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.integer "occurrence_count", default: 1, null: false
    t.string "controller_name"
    t.string "action_name"
    t.string "app_version"
    t.string "git_sha"
    t.integer "priority_score"
    t.float "similarity_score"
    t.string "backtrace_signature"
    t.integer "application_id", null: false
    t.index [ "application_id", "occurred_at" ], name: "index_error_logs_on_app_occurred"
    t.index [ "application_id", "resolved" ], name: "index_error_logs_on_app_resolved"
    t.index [ "application_id" ], name: "index_rails_error_dashboard_error_logs_on_application_id"
    t.index [ "app_version" ], name: "index_rails_error_dashboard_error_logs_on_app_version"
    t.index [ "backtrace_signature" ], name: "index_rails_error_dashboard_error_logs_on_backtrace_signature"
    t.index [ "controller_name", "action_name", "error_hash" ], name: "index_error_logs_on_controller_action_hash"
    t.index [ "error_hash", "resolved", "occurred_at" ], name: "index_error_logs_on_hash_resolved_occurred"
    t.index [ "error_hash" ], name: "index_rails_error_dashboard_error_logs_on_error_hash"
    t.index [ "error_type", "occurred_at" ], name: "index_error_logs_on_error_type_and_occurred_at"
    t.index [ "error_type" ], name: "index_rails_error_dashboard_error_logs_on_error_type"
    t.index [ "first_seen_at" ], name: "index_rails_error_dashboard_error_logs_on_first_seen_at"
    t.index [ "git_sha" ], name: "index_rails_error_dashboard_error_logs_on_git_sha"
    t.index [ "last_seen_at" ], name: "index_rails_error_dashboard_error_logs_on_last_seen_at"
    t.index [ "occurred_at" ], name: "index_rails_error_dashboard_error_logs_on_occurred_at"
    t.index [ "occurrence_count" ], name: "index_rails_error_dashboard_error_logs_on_occurrence_count"
    t.index [ "platform", "occurred_at" ], name: "index_error_logs_on_platform_and_occurred_at"
    t.index [ "platform" ], name: "index_rails_error_dashboard_error_logs_on_platform"
    t.index [ "priority_score" ], name: "index_rails_error_dashboard_error_logs_on_priority_score"
    t.index [ "resolved", "occurred_at" ], name: "index_error_logs_on_resolved_and_occurred_at"
    t.index [ "resolved" ], name: "index_rails_error_dashboard_error_logs_on_resolved"
    t.index [ "similarity_score" ], name: "index_rails_error_dashboard_error_logs_on_similarity_score"
    t.index [ "user_id" ], name: "index_rails_error_dashboard_error_logs_on_user_id"
  end

  create_table "rails_error_dashboard_error_occurrences", force: :cascade do |t|
    t.integer "error_log_id", null: false
    t.datetime "occurred_at", null: false
    t.integer "user_id"
    t.string "request_id"
    t.string "session_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "error_log_id" ], name: "index_error_occurrences_on_error_log"
    t.index [ "occurred_at", "error_log_id" ], name: "index_error_occurrences_on_time_and_error"
    t.index [ "request_id" ], name: "index_error_occurrences_on_request"
    t.index [ "user_id" ], name: "index_error_occurrences_on_user"
  end

  add_foreign_key "rails_error_dashboard_cascade_patterns", "rails_error_dashboard_error_logs", column: "child_error_id"
  add_foreign_key "rails_error_dashboard_cascade_patterns", "rails_error_dashboard_error_logs", column: "parent_error_id"
  add_foreign_key "rails_error_dashboard_error_comments", "rails_error_dashboard_error_logs", column: "error_log_id"
  add_foreign_key "rails_error_dashboard_error_logs", "rails_error_dashboard_applications", column: "application_id"
  add_foreign_key "rails_error_dashboard_error_occurrences", "rails_error_dashboard_error_logs", column: "error_log_id"
end
