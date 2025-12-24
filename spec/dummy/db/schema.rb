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

ActiveRecord::Schema[8.1].define(version: 2025_12_24_000001) do
  create_table "rails_error_dashboard_error_logs", force: :cascade do |t|
    t.text "backtrace"
    t.datetime "created_at", null: false
    t.string "environment", null: false
    t.string "error_type", null: false
    t.string "ip_address"
    t.text "message", null: false
    t.datetime "occurred_at", null: false
    t.string "platform"
    t.text "request_params"
    t.text "request_url"
    t.text "resolution_comment"
    t.string "resolution_reference"
    t.boolean "resolved", default: false, null: false
    t.datetime "resolved_at"
    t.string "resolved_by_name"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.integer "user_id"
    t.index ["environment"], name: "index_rails_error_dashboard_error_logs_on_environment"
    t.index ["error_type"], name: "index_rails_error_dashboard_error_logs_on_error_type"
    t.index ["occurred_at"], name: "index_rails_error_dashboard_error_logs_on_occurred_at"
    t.index ["platform"], name: "index_rails_error_dashboard_error_logs_on_platform"
    t.index ["resolved"], name: "index_rails_error_dashboard_error_logs_on_resolved"
    t.index ["user_id"], name: "index_rails_error_dashboard_error_logs_on_user_id"
  end
end
