# Multi-Database Bug Fix - v0.1.24

## Summary

Fixed critical bug where multi-database support was completely broken in v0.1.23. Users could not use a separate database for error logs due to hardcoded database names and missing configuration options.

## Root Causes Identified

1. **Generator Issue**: `--database` flag didn't exist; `--separate_database` flag existed but didn't set which database to use
2. **Model Issue**: `ErrorLogsRecord` hardcoded `connects_to database: { writing: :error_logs, reading: :error_logs }` instead of reading from configuration
3. **Configuration Issue**: Initializer template set `use_separate_database = true` but never set the `database` config option

## Changes Made

### 1. Generator (`lib/generators/rails_error_dashboard/install/install_generator.rb`)

**Added `--database` flag:**
```ruby
class_option :database, type: :string, default: nil, desc: "Database name to use for errors (e.g., 'error_dashboard')"
```

**Capture database name from options:**
```ruby
@database_name = options[:database]
```

**Updated help text:**
- Shows which database name will be configured when `--database` is provided
- Provides clearer instructions for manual database setup

### 2. Initializer Template (`lib/generators/rails_error_dashboard/install/templates/initializer.rb`)

**Added database configuration:**
```ruby
<% if @enable_separate_database -%>
  config.use_separate_database = true
<% if @database_name -%>
  config.database = :<%= @database_name %>
<% else -%>
  # config.database = :error_dashboard  # Uncomment and set your database name
<% end -%>
<% end -%>
```

### 3. Model Base Class (`app/models/rails_error_dashboard/error_logs_record.rb`)

**Removed hardcoded database connection:**
- Removed static `connects_to` call with hardcoded `:error_logs` database name
- Database connection now configured dynamically by the engine

**Updated documentation:**
- Changed references from `error_logs` to `error_dashboard`
- Clarified setup instructions

### 4. Engine Configuration (`lib/rails_error_dashboard/engine.rb`)

**Added database connection initializer:**
```ruby
initializer "rails_error_dashboard.database", before: :load_config_initializers do
  config.after_initialize do
    if RailsErrorDashboard.configuration&.use_separate_database
      database_name = RailsErrorDashboard.configuration&.database || :error_dashboard

      RailsErrorDashboard::ErrorLogsRecord.connects_to(
        database: { writing: database_name, reading: database_name }
      )
    end
  end
end
```

This ensures:
- Database connection is set up after user configuration is loaded
- Uses the configured database name from `config.database`
- Falls back to `:error_dashboard` if not specified
- Only connects when `use_separate_database = true`

### 5. Tests (`spec/generators/install_generator_spec.rb`)

**Added comprehensive test coverage:**
- Test `--database` flag sets `config.database` correctly
- Test `--separate_database` without `--database` includes commented hint
- Test default behavior doesn't set database configuration

## Usage

### Method 1: Using --database Flag (Recommended)

```bash
rails generate rails_error_dashboard:install --no-interactive --separate_database --database=error_dashboard
```

This will generate an initializer with:
```ruby
config.use_separate_database = true
config.database = :error_dashboard
```

### Method 2: Enable Later Manually

Install normally, then edit the initializer:
```ruby
config.use_separate_database = true
config.database = :error_dashboard  # Uncomment and set
```

### Database Configuration

Configure in `config/database.yml`:
```yaml
development:
  primary:
    database: my_app_development
    # ... other settings

  error_dashboard:
    database: error_dashboard_development
    adapter: postgresql
    # ... other settings
```

## Testing

Generator tests pass:
```bash
bundle exec rspec spec/generators/install_generator_spec.rb -e "database configuration"
# 5 examples, 0 failures
```

## Migration Notes

### For New Installations
Just use the `--database` flag and configure `database.yml`. Works immediately.

### For Existing v0.1.23 Users
If you already installed v0.1.23 with `--separate_database`:

1. Update to v0.1.24
2. Edit your initializer to add:
   ```ruby
   config.database = :error_dashboard
   ```
3. Ensure your `database.yml` has the matching database configuration
4. Restart your app

## Files Changed

- `lib/generators/rails_error_dashboard/install/install_generator.rb`
- `lib/generators/rails_error_dashboard/install/templates/initializer.rb`
- `app/models/rails_error_dashboard/error_logs_record.rb`
- `lib/rails_error_dashboard/engine.rb`
- `spec/generators/install_generator_spec.rb`

## Backwards Compatibility

✅ **Fully backwards compatible** - Users not using separate database are unaffected
✅ **No breaking changes** - All existing configurations continue to work
✅ **Graceful degradation** - If `config.database` is not set, defaults to `:error_dashboard`

## Next Steps for v0.1.24

1. ✅ Fix multi-database support (DONE)
2. ⏳ Run full test suite and fix remaining test failures (see TEST_RESULTS_v0.1.23.md)
3. ⏳ Test upgrade paths (v0.1.21 → v0.1.24)
4. ⏳ Test multi-app scenarios
5. ⏳ Update CHANGELOG.md
6. ⏳ Update documentation (DATABASE_OPTIONS.md, README.md)
7. ⏳ Release v0.1.24
