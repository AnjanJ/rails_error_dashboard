# frozen_string_literal: true

# Say WHICH occurrence supplied the diagnostic snapshot a group displays.
#
# An ErrorLog row is a group, but its breadcrumbs, system health, locals,
# instance variables and request context describe ONE moment of failure. They
# are refreshed by each occurrence that carries them, and deliberately left
# alone by one that does not (a storm :lite capture, or a feature switched
# off) -- keeping a useful snapshot rather than blanking it is right.
#
# What was missing is provenance. The page labelled that collection as the
# error's context without saying which event it came from, so a row could show
# a new request URL beside a previous occurrence's user id and locals with
# nothing to indicate they came from different requests.
#
#   context_captured_at  when the displayed snapshot was captured
#   context_fidelity     how complete that capture was:
#                          "full"    -- the normal path, everything captured
#                          "lite"    -- storm shedding: error + occurrence row
#                                       only, context payloads shed
#                          "minimal" -- reconstructed by the storm flush from a
#                                       counted-only exemplar (no backtrace,
#                                       no context at all)
#
# Both are nullable: rows captured before this migration have no recorded
# provenance, and the view says so rather than inventing one.
class AddContextProvenanceToErrorLogs < ActiveRecord::Migration[7.0]
  TABLE = :rails_error_dashboard_error_logs

  def change
    return unless table_exists?(TABLE)

    unless column_exists?(TABLE, :context_captured_at)
      add_column TABLE, :context_captured_at, :datetime
    end

    unless column_exists?(TABLE, :context_fidelity)
      # 10: "full" / "lite" / "minimal".
      add_column TABLE, :context_fidelity, :string, limit: 10
    end
  end
end
