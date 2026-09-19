# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # How many EVENTS happened inside a time window.
    #
    # The distinction this class exists to make: an ErrorLog row is a GROUP,
    # and its occurred_at is FIRST-SEEN -- written once at creation and never
    # rewritten when the error recurs. Filtering groups by occurred_at and
    # summing occurrence_count therefore answers "how much lifetime volume do
    # the groups born in this window carry?", which is not the same question as
    # "how many events happened in this window?". An error first seen at 23:59
    # that recurs at 00:01 reported zero errors today and two yesterday.
    #
    # An event lands in exactly one of three places, and the window total is
    # the sum of all three:
    #
    #   1. an ErrorOccurrence row     -- ordinary captures, with a real
    #                                    per-event timestamp
    #   2. an EventCount bucket       -- storm-shed events, which write no
    #                                    occurrence row by design; the bucket
    #                                    is their timestamp
    #   3. the group's own count      -- rows from before occurrence tracking
    #                                    existed, which have neither of the
    #                                    above. Counted against the group's
    #                                    occurred_at, which for such a row is
    #                                    the best (and only) timestamp there is
    #
    # Nothing is double counted: (1) and (2) are written by mutually exclusive
    # paths, and (3) only ever covers the remainder of a group that has no
    # per-event record at all.
    class EventVolume
      # @param scope [ActiveRecord::Relation] an ErrorLog scope (already
      #   filtered by application, if applicable)
      # @param from [Time]
      # @param to [Time, nil] exclusive upper bound; open-ended when nil
      # @return [Integer]
      def self.in_window(scope, from, to = nil)
        new(scope, from, to).count
      end

      # Same window, bucketed by day: { Date => Integer }.
      def self.by_day(scope, from, to = nil)
        new(scope, from, to).by_day
      end

      def initialize(scope, from, to = nil)
        @scope = scope
        @from = from
        @to = to
      end

      def count
        occurrence_events + bucketed_events + untracked_events
      end

      def by_day
        totals = Hash.new(0)
        occurrence_events_by_day.each { |day, n| totals[day] += n }
        bucketed_events_by_day.each { |day, n| totals[day] += n }
        untracked_events_by_day.each { |day, n| totals[day] += n }
        totals
      end

      private

      # A SUBQUERY, not a plucked array of ids: the group set is unbounded and
      # loading it into Ruby to pass back as an IN list is the shape that has
      # caused unbounded-memory bugs in this codebase before. The database
      # keeps the id set on its own side.
      def group_ids
        @group_ids ||= @scope.select(:id)
      end

      # (1) Ordinary captures.
      def occurrence_events
        return 0 unless occurrences_available?

        window(ErrorOccurrence.where(error_log_id: group_ids), ErrorOccurrence.table_name).count
      end

      def occurrence_events_by_day
        return {} unless occurrences_available?

        window(ErrorOccurrence.where(error_log_id: group_ids), ErrorOccurrence.table_name)
          .group(day_expression(ErrorOccurrence.table_name, "occurred_at")).count
          .transform_keys { |k| to_date(k) }
      end

      # (2) Storm-shed events.
      def bucketed_events
        return 0 unless buckets_available?

        window(EventCount.where(error_log_id: group_ids), EventCount.table_name, column: "bucket_at")
          .sum(:count)
      end

      def bucketed_events_by_day
        return {} unless buckets_available?

        window(EventCount.where(error_log_id: group_ids), EventCount.table_name, column: "bucket_at")
          .group(day_expression(EventCount.table_name, "bucket_at")).sum(:count)
          .transform_keys { |k| to_date(k) }
      end

      # (3) Groups with no per-event record of any kind: rows created before
      # occurrence tracking, and rows written directly. Their occurrence_count
      # is the only evidence the events happened, and the group's own
      # occurred_at is the only timestamp available for them.
      def untracked_groups
        @untracked_groups ||= begin
          # Only groups whose own occurred_at falls in the window can
          # contribute here at all, so the scan is bounded by the window rather
          # than by the whole table.
          #
          # One SELECT with two correlated sub-selects, rather than three
          # separate round trips: this runs on the capture path (the stats
          # broadcast recomputes it) and the dashboard asks for several windows
          # per render, so a per-window query count multiplies quickly.
          rows = ErrorLog.connection.select_all(untracked_sql(window(@scope, ErrorLog.table_name)))
          rows.filter_map do |row|
            remainder = row["occurrence_count"].to_i - row["tracked"].to_i
            next if remainder <= 0

            [ row["id"], remainder, to_time(row["occurred_at"]) ]
          end
        end
      end

      def untracked_sql(candidates)
        logs = ErrorLog.table_name
        occurrence_term =
          if occurrences_available?
            "(SELECT COUNT(*) FROM #{ErrorOccurrence.table_name} o " \
            "WHERE o.error_log_id = #{logs}.id)"
          else
            "0"
          end
        bucket_term =
          if buckets_available?
            "(SELECT COALESCE(SUM(b.count), 0) FROM #{EventCount.table_name} b " \
            "WHERE b.error_log_id = #{logs}.id)"
          else
            "0"
          end

        candidates
          .select(Arel.sql("#{logs}.id, #{logs}.occurrence_count, #{logs}.occurred_at, " \
                           "#{occurrence_term} + #{bucket_term} AS tracked"))
          .to_sql
      end

      def to_time(value)
        return value if value.respond_to?(:to_date) && !value.is_a?(String)

        Time.zone ? Time.zone.parse(value.to_s) : Time.parse(value.to_s)
      rescue StandardError
        nil
      end

      def untracked_events
        untracked_groups.sum { |_id, remainder, _occurred_at| remainder }
      end

      def untracked_events_by_day
        totals = Hash.new(0)
        untracked_groups.each do |_id, remainder, occurred_at|
          next unless occurred_at

          totals[occurred_at.to_date] += remainder
        end
        totals
      end

      def window(relation, table, column: "occurred_at")
        relation = relation.where("#{table}.#{column} >= ?", @from)
        @to ? relation.where("#{table}.#{column} < ?", @to) : relation
      end

      # Grouping by day has to happen in SQL -- loading rows to bucket them in
      # Ruby is exactly the unbounded-memory shape this codebase avoids.
      def day_expression(table, column)
        Arel.sql(
          case ErrorLog.connection.adapter_name.downcase
          when /postgres/ then "DATE(#{table}.#{column})"
          when /mysql|trilogy/ then "DATE(#{table}.#{column})"
          else "date(#{table}.#{column})"
          end
        )
      end

      def to_date(value)
        return value if value.is_a?(Date)

        value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
      rescue StandardError
        value
      end

      def occurrences_available?
        return @occurrences_available if defined?(@occurrences_available)

        @occurrences_available = defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
      rescue StandardError
        @occurrences_available = false
      end

      def buckets_available?
        return @buckets_available if defined?(@buckets_available)

        @buckets_available = defined?(EventCount) && EventCount.table_exists?
      rescue StandardError
        @buckets_available = false
      end
    end
  end
end
