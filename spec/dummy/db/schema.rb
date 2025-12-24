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

ActiveRecord::Schema[8.0].define(version: 2025_12_24_101217) do
  create_table "rails_error_dashboard_error_logs", force: :cascade do |t|
    t.string "error_type", null: false
    t.text "message", null: false
    t.text "backtrace"
    t.integer "user_id"
    t.text "request_url"
    t.text "request_params"
    t.text "user_agent"
    t.string "ip_address"
    t.string "environment", null: false
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
    t.index ["controller_name", "action_name", "error_hash"], name: "index_error_logs_on_controller_action_hash"
    t.index ["environment"], name: "index_rails_error_dashboard_error_logs_on_environment"
    t.index ["error_hash"], name: "index_rails_error_dashboard_error_logs_on_error_hash"
    t.index ["error_type"], name: "index_rails_error_dashboard_error_logs_on_error_type"
    t.index ["first_seen_at"], name: "index_rails_error_dashboard_error_logs_on_first_seen_at"
    t.index ["last_seen_at"], name: "index_rails_error_dashboard_error_logs_on_last_seen_at"
    t.index ["occurred_at"], name: "index_rails_error_dashboard_error_logs_on_occurred_at"
    t.index ["occurrence_count"], name: "index_rails_error_dashboard_error_logs_on_occurrence_count"
    t.index ["platform"], name: "index_rails_error_dashboard_error_logs_on_platform"
    t.index ["resolved"], name: "index_rails_error_dashboard_error_logs_on_resolved"
    t.index ["user_id"], name: "index_rails_error_dashboard_error_logs_on_user_id"
  end
end
