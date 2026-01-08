class BackfillApplicationForExistingErrors < ActiveRecord::Migration[7.0]
  def up
    return if RailsErrorDashboard::ErrorLog.count.zero?

    # Create default application
    default_name = ENV['APPLICATION_NAME'] ||
                   (defined?(Rails) && Rails.application.class.module_parent_name) ||
                   'Legacy Application'

    app = RailsErrorDashboard::Application.find_or_create_by!(name: default_name) do |a|
      a.description = 'Auto-created during migration for existing errors'
    end

    # Backfill in batches
    RailsErrorDashboard::ErrorLog.where(application_id: nil).in_batches(of: 1000) do |batch|
      batch.update_all(application_id: app.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
