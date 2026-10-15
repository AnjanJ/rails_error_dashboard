class BackfillApplicationForExistingErrors < ActiveRecord::Migration[7.0]
  def up
    return if RailsErrorDashboard::ErrorLog.count.zero?

    # Create default application
    # The name new errors are captured under, config.application_name first,
    # so old and new errors land in the same Application
    default_name = RailsErrorDashboard.resolved_application_name

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
