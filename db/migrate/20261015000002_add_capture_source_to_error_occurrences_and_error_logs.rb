# frozen_string_literal: true

# Where each capture came from: "server" for RED's own captures (middleware,
# the Rails.error subscriber, jobs, crash import), "client" for errors sent
# through ManualErrorReporter by a browser, mobile app or other client.
#
#   error_occurrences.capture_source  how this occurrence was captured
#   error_logs.backtrace_source       where the backtrace the error page shows
#                                     came from (the group's backtrace can be
#                                     replaced by a later capture's)
#
# A client's backtrace describes code that ran on the client, so the features
# that read this app's source files for a frame (View Source, git blame, the
# snippets in Copy for LLM and AI help) skip it.
#
# Nullable, no default: NULL is a row from before this migration and reads as
# server, which is how those rows have always been treated. No index: nothing
# queries by it. Not part of the fingerprint: a client report and a server
# capture of the same error stay one group.
#
# up/down rather than `change`: the column_exists? guards that make `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddCaptureSourceToErrorOccurrencesAndErrorLogs < ActiveRecord::Migration[7.0]
  COLUMNS = {
    rails_error_dashboard_error_occurrences: :capture_source,
    rails_error_dashboard_error_logs: :backtrace_source
  }.freeze

  def up
    COLUMNS.each do |table, column|
      next unless table_exists?(table)
      next if column_exists?(table, column)

      add_column table, column, :string, limit: 10
    end
  end

  def down
    COLUMNS.each do |table, column|
      next unless table_exists?(table)
      next unless column_exists?(table, column)

      remove_column table, column
    end
  end
end
