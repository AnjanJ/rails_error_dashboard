# frozen_string_literal: true

# One row per (locale, key, application) the host app failed to translate.
#
# A missing translation is not an error: Rails renders "translation missing"
# (or the humanized key) and the request succeeds, so it never reaches
# error_logs and nothing in the dashboard would otherwise show it. The
# tracker counts misses in memory and upserts them here at the end of the
# request or job that produced them -- a loop rendering a missing key a
# thousand times is one UPDATE, not a thousand INSERTs.
class CreateMissingTranslations < ActiveRecord::Migration[7.0]
  def change
    # Guard against the squashed schema migration having already created this
    # table -- without it, every later migration is silently cancelled.
    return if table_exists?(:rails_error_dashboard_missing_translations)

    create_table :rails_error_dashboard_missing_translations do |t|
      # BCP 47 tags ("pt-BR", "zh-Hans-CN", "en-US-x-twain") fit in 35.
      t.string   :locale,          null: false, limit: 35
      # The full dotted key as I18n normalised it ("users.show.greeting").
      # Capped at 191 so the unique upsert index stays inside MySQL's
      # 3072-byte utf8mb4 limit: (35 + 191) * 4 + application_id. The tracker
      # truncates before the value reaches the index.
      t.string   :translation_key, null: false, limit: 191
      # First host call site seen for this key ("app/views/users/show.html.erb:12").
      # First-write-wins; not part of the row's identity.
      t.string   :source,          limit: 250
      t.bigint   :miss_count,      null: false, default: 0
      t.datetime :first_seen_at,   null: false
      t.datetime :last_seen_at,    null: false
      # Nullable: a miss recorded before application scoping, or with no
      # application_name configured, applies to the whole install.
      t.bigint   :application_id
      t.timestamps
    end

    # Named explicitly: an auto-generated name would exceed PostgreSQL's
    # 63-character limit and fail during the HOST app's deploy.
    add_index :rails_error_dashboard_missing_translations,
              [ :locale, :translation_key, :application_id ],
              unique: true,
              name: "index_red_missing_translations_upsert_key"

    # The dashboard reads "misses seen in the last N days" and retention
    # prunes by the same column.
    add_index :rails_error_dashboard_missing_translations,
              :last_seen_at,
              name: "index_red_missing_translations_on_last_seen_at"
  end
end
