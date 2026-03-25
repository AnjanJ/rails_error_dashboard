# frozen_string_literal: true

# Fix MySQL "Specified key was too long" error on the swallowed_exceptions
# composite unique index. The original columns (varchar 255 + 500 + 500)
# total 5042 bytes under utf8mb4, exceeding MySQL's 3072-byte InnoDB limit.
#
# Reduces all three string columns to limit: 250, bringing the total to
# 3022 bytes (250 * 4 * 3 + 6 length prefixes + 16 datetime/bigint).
#
# See: https://github.com/AnjanJ/rails_error_dashboard/issues/96
class FixSwallowedExceptionsIndexForMysql < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:rails_error_dashboard_swallowed_exceptions)

    # Remove the oversized index if it exists (it may not exist on MySQL
    # since the original migration would have failed at this point)
    if index_exists?(:rails_error_dashboard_swallowed_exceptions, name: "index_swallowed_exceptions_upsert_key")
      remove_index :rails_error_dashboard_swallowed_exceptions, name: "index_swallowed_exceptions_upsert_key"
    end

    # Shrink columns to fit within MySQL's 3072-byte index key limit
    change_column :rails_error_dashboard_swallowed_exceptions, :exception_class, :string, null: false, limit: 250
    change_column :rails_error_dashboard_swallowed_exceptions, :raise_location, :string, null: false, limit: 250
    change_column :rails_error_dashboard_swallowed_exceptions, :rescue_location, :string, limit: 250

    # Re-add the index with the smaller columns
    add_index :rails_error_dashboard_swallowed_exceptions,
              [ :exception_class, :raise_location, :rescue_location, :period_hour, :application_id ],
              unique: true,
              name: "index_swallowed_exceptions_upsert_key"
  end

  def down
    return unless table_exists?(:rails_error_dashboard_swallowed_exceptions)

    if index_exists?(:rails_error_dashboard_swallowed_exceptions, name: "index_swallowed_exceptions_upsert_key")
      remove_index :rails_error_dashboard_swallowed_exceptions, name: "index_swallowed_exceptions_upsert_key"
    end

    change_column :rails_error_dashboard_swallowed_exceptions, :exception_class, :string, null: false
    change_column :rails_error_dashboard_swallowed_exceptions, :raise_location, :string, null: false, limit: 500
    change_column :rails_error_dashboard_swallowed_exceptions, :rescue_location, :string, limit: 500

    add_index :rails_error_dashboard_swallowed_exceptions,
              [ :exception_class, :raise_location, :rescue_location, :period_hour, :application_id ],
              unique: true,
              name: "index_swallowed_exceptions_upsert_key"
  end
end
