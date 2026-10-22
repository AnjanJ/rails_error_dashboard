# frozen_string_literal: true

# Abstract base class for models stored in the error dashboard database
#
# By default, this connects to the same database as the main application.
#
# To enable a separate error dashboard database:
# 1. Set config.use_separate_database = true in the gem configuration
# 2. Set config.database = :error_dashboard in the gem configuration
# 3. Add an "error_dashboard:" entry in config/database.yml
# 4. Run: rails db:create:error_dashboard
# 5. Run: rails db:migrate:error_dashboard
#
# For multi-app setups, point all apps' database.yml "error_dashboard:" entry
# to the same physical database. Each app is identified by config.application_name.
#
# Run "rails error_dashboard:verify" to check your setup.
#
# Benefits of separate database:
# - Performance isolation (error logging doesn't slow down user requests)
# - Independent scaling (can put error DB on separate server)
# - Multi-app support (centralized error tracking across multiple Rails apps)
# - Different retention policies (archive old errors without affecting main data)
#
# Trade-offs:
# - No foreign keys between error_logs and users tables
# - No joins across databases (Rails handles with separate queries)
# - Slightly more complex operations (need to manage 2 databases)

module RailsErrorDashboard
  class ErrorLogsRecord < ActiveRecord::Base
    self.abstract_class = true

    # Database connection will be configured by the engine initializer
    # after the user's configuration is loaded
    # See lib/rails_error_dashboard/engine.rb

    # Read-side half of the invalid-bytes defence. Capture scrubs what it
    # writes, but SQLite and MySQL will happily hold a row written before that
    # (or by anything else), and one such string takes down every page that
    # renders it: ERB raises "invalid byte sequence in UTF-8". Scrubbing on load
    # makes the page render whether or not the operator has run
    # error_dashboard:scrub_invalid_encoding yet. In memory only: nothing is
    # written, and the record is not left dirty.
    after_find :scrub_invalid_strings

    # Names of the attributes the load-time scrub had to repair, so that
    # Commands::ScrubInvalidEncoding can persist the repair: once the values
    # are clean in memory, re-reading them can no longer tell a bad row apart.
    # @return [Array<String>]
    def invalid_encoding_attributes
      @invalid_encoding_attributes || []
    end

    # Rails' default for a string column when the adapter has one (MySQL).
    DEFAULT_STRING_LIMIT = 255

    # Truncate string-typed attributes to their column limits. MySQL in strict
    # mode rejects an over-long value outright, the capture path rescues the
    # failure, and the error is silently lost — over a 300-character app
    # version. Columns without a declared limit are clamped to the Rails
    # default so behaviour is the same on every adapter. Text columns are
    # untouched. Identity (error_hash) is computed from the raw values before
    # this runs, so clamping display metadata never changes grouping.
    # @param attributes [Hash] attribute name => value
    # @return [Hash] a copy with over-long strings truncated
    def self.clamp_string_attributes(attributes)
      limits = string_column_limits
      attributes.each_with_object({}) do |(name, value), clamped|
        limit = limits[name.to_s]
        clamped[name] = if limit && value.is_a?(String) && value.length > limit
          value[0, limit]
        else
          value
        end
      end
    rescue => e
      RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] clamp_string_attributes failed: #{e.message}")
      attributes
    end

    # @return [Hash] column name => character limit, string columns only (memoized per class)
    def self.string_column_limits
      @string_column_limits ||= columns_hash.each_with_object({}) do |(name, column), limits|
        limits[name] = column.limit || DEFAULT_STRING_LIMIT if column.type == :string
      end
    end

    # Bytes a TEXT column holds on MySQL, the tightest adapter RED supports.
    TEXT_LIMIT = 65_535

    # Text columns holding JSON. Cutting one would leave a payload nothing can
    # parse, so an oversized one is left out instead: context is RED's own data
    # to give up, and the error row survives without it.
    JSON_TEXT_COLUMNS = %w[
      request_params exception_cause environment_info breadcrumbs system_health
      local_variables instance_variables top_fingerprints dump_data
    ].freeze

    # The text-column half of clamp_string_attributes. MySQL in strict mode
    # rejects the whole INSERT when one TEXT value is over 65,535 bytes, and the
    # capture path rescues the failure, so a single oversized payload lost the
    # error. The same limit applies on every adapter, so the behaviour doesn't
    # depend on the database. Run on the final attributes, just before writing.
    # @param attributes [Hash] attribute name => value
    # @return [Hash] a copy with oversized text cut (plain text) or left out (JSON)
    def self.clamp_text_attributes(attributes)
      columns = text_columns
      attributes.each_with_object({}) do |(name, value), clamped|
        clamped[name] = if value.is_a?(String) && value.bytesize > TEXT_LIMIT && columns.include?(name.to_s)
          JSON_TEXT_COLUMNS.include?(name.to_s) ? nil : Services::CaptureLimits.cut_bytes(value, TEXT_LIMIT)
        else
          value
        end
      end
    rescue => e
      RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] clamp_text_attributes failed: #{e.message}")
      attributes
    end

    # @return [Set<String>] text column names (memoized per class)
    def self.text_columns
      @text_columns ||= columns_hash.each_with_object(Set.new) do |(name, column), names|
        names << name if column.type == :text
      end
    end

    private

    def scrub_invalid_strings
      @attributes.each_value do |attribute|
        value = attribute.value_before_type_cast
        next unless value.is_a?(String)
        next if value.encoding == Encoding::UTF_8 && value.valid_encoding? && !value.include?("\0")

        name = attribute.name
        self[name] = Services::EncodingSanitizer.scrub(value)
        clear_attribute_changes([ name ])
        (@invalid_encoding_attributes ||= []) << name
      end
    rescue => e
      RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] scrub on load failed: #{e.class}: #{e.message}")
    end
  end
end
