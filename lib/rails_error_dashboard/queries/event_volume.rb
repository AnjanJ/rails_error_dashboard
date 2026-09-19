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

      # Same window, grouped by a column on the GROUP row (error_type,
      # platform, environment): { value => Integer }.
      #
      # Every breakdown has to sum the same three terms as the headline total,
      # or a page's parts stop adding up to its whole. Exposing one primitive
      # is what stops each call site reimplementing that sum and drifting --
      # which is precisely how the Analytics page came to disagree with the
      # Overview.
      def self.by_group_attribute(scope, column, from, to = nil)
        new(scope, from, to).by_group_attribute(column)
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

      # Events in the window, bucketed by hour-of-day (0..23) against each
      # event's OWN timestamp -- the diurnal curve, not a time series.
      # The hour is LOCAL for the same reason the day is: an operator asking
      # when their errors peak means their own clock. Bucketed in Ruby from the
      # windowed, already-aggregated rows so the offset used is the one in
      # force at each instant.
      def by_hour_of_day
        zone = self.class.reporting_zone
        totals = Hash.new(0)
        (0..23).each { |h| totals[h] = 0 }

        occurrence_events_by_hour.each { |ts, n| totals[local_hour(ts, zone)] += n }
        bucketed_events_by_hour.each { |ts, n| totals[local_hour(ts, zone)] += n }
        untracked_groups.each do |_id, remainder, occurred_at|
          totals[occurred_at.in_time_zone(zone).hour] += remainder if occurred_at
        end
        totals
      end

      # Events in the window, grouped by a column on the ErrorLog row.
      #
      # All three terms are joined back to their group so they can be grouped
      # by the group's own attribute: occurrence rows and buckets carry no
      # error_type of their own. Aggregation stays in SQL (NFR-6) -- the only
      # thing loaded into Ruby is the grouped result.
      def by_group_attribute(column)
        totals = Hash.new(0)
        occurrence_events_by_attribute(column).each { |k, n| totals[k] += n }
        bucketed_events_by_attribute(column).each { |k, n| totals[k] += n }
        untracked_events_by_attribute(column).each { |k, n| totals[k] += n }
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

        rows = window(ErrorOccurrence.where(error_log_id: group_ids), ErrorOccurrence.table_name)
               .group(day_expression(ErrorOccurrence.table_name, "occurred_at")).count

        ruby_side_day_bucketing? ? group_by_local_day(rows) : rows.transform_keys { |k| to_date(k) }
      end

      # (2) Storm-shed events.
      def bucketed_events
        return 0 unless buckets_available?

        window(EventCount.where(error_log_id: group_ids), EventCount.table_name, column: "bucket_at")
          .sum(:count)
      end

      def bucketed_events_by_day
        return {} unless buckets_available?

        rows = window(EventCount.where(error_log_id: group_ids), EventCount.table_name, column: "bucket_at")
               .group(day_expression(EventCount.table_name, "bucket_at")).sum(:count)

        ruby_side_day_bucketing? ? group_by_local_day(rows) : rows.transform_keys { |k| to_date(k) }
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

      # Grouped by the raw timestamp so the LOCAL hour can be derived per row
      # (see by_hour_of_day). The window still bounds what is aggregated; only
      # the grouped result reaches Ruby.
      def occurrence_events_by_hour
        return {} unless occurrences_available?

        window(ErrorOccurrence.where(error_log_id: group_ids), ErrorOccurrence.table_name)
          .group("#{ErrorOccurrence.table_name}.occurred_at").count
      end

      def bucketed_events_by_hour
        return {} unless buckets_available?

        window(EventCount.where(error_log_id: group_ids), EventCount.table_name, column: "bucket_at")
          .group("#{EventCount.table_name}.bucket_at").sum(:count)
      end

      def local_hour(value, zone)
        time = to_time(value)
        time ? time.in_time_zone(zone).hour : 0
      end

      # The three by-attribute terms. Each joins back to ErrorLog because the
      # attribute being grouped by lives on the GROUP, not on the event row.
      def occurrence_events_by_attribute(column)
        return {} unless occurrences_available?

        logs = ErrorLog.table_name
        window(
          ErrorOccurrence.where(error_log_id: group_ids)
                         .joins("INNER JOIN #{logs} ON #{logs}.id = #{ErrorOccurrence.table_name}.error_log_id"),
          ErrorOccurrence.table_name
        ).group("#{logs}.#{column}").count
      end

      def bucketed_events_by_attribute(column)
        return {} unless buckets_available?

        logs = ErrorLog.table_name
        window(
          EventCount.where(error_log_id: group_ids)
                    .joins("INNER JOIN #{logs} ON #{logs}.id = #{EventCount.table_name}.error_log_id"),
          EventCount.table_name,
          column: "bucket_at"
        ).group("#{logs}.#{column}").sum(:count)
      end

      # The untracked remainder is already resolved to (id, remainder), so the
      # attribute is fetched for just those ids -- a bounded set, since only
      # groups whose own occurred_at falls in the window can contribute.
      def untracked_events_by_attribute(column)
        rows = untracked_groups
        return {} if rows.empty?

        attributes = ErrorLog.where(id: rows.map(&:first)).pluck(:id, column).to_h
        totals = Hash.new(0)
        rows.each { |id, remainder, _occurred_at| totals[attributes[id]] += remainder }
        totals
      end

      def untracked_events
        untracked_groups.sum { |_id, remainder, _occurred_at| remainder }
      end

      # Already in Ruby, so the zone conversion is direct -- and uses the
      # offset in force at each row's own instant.
      def untracked_events_by_day
        zone = self.class.reporting_zone
        totals = Hash.new(0)
        untracked_groups.each do |_id, remainder, occurred_at|
          next unless occurred_at

          totals[occurred_at.in_time_zone(zone).to_date] += remainder
        end
        totals
      end

      def window(relation, table, column: "occurred_at")
        relation = relation.where("#{table}.#{column} >= ?", @from)
        @to ? relation.where("#{table}.#{column} < ?", @to) : relation
      end

      # Grouping by day has to happen in SQL -- loading rows to bucket them in
      # Ruby is exactly the unbounded-memory shape this codebase avoids.
      # The reporting zone: one definition, used for BOTH the SQL bucket key
      # and the Ruby-side window boundaries, so the two cannot disagree.
      def self.reporting_zone
        Time.zone || ActiveSupport::TimeZone["UTC"]
      end

      # Group by calendar day IN THE APPLICATION TIME ZONE.
      #
      # Timestamps are stored in UTC. A bare DATE(column) therefore buckets by
      # UTC day while the caller looks up Date.current in Time.zone -- at 00:15
      # in Asia/Kolkata a fresh capture is stored as 18:45 the previous day UTC,
      # so "today" reported zero. The offset must also be the one in force AT
      # EACH ROW'S OWN TIMESTAMP, not one current offset applied to the whole
      # window, or a window spanning a DST change misplaces every row on one
      # side of it.
      #
      # PostgreSQL and MySQL have a tz database and do this per row natively.
      # SQLite has neither AT TIME ZONE nor CONVERT_TZ, and its 'localtime'
      # modifier uses the SERVER's zone rather than the application's -- so
      # there the conversion is done in Ruby, where the zone object knows each
      # instant's true offset. That path is bounded: it groups an already
      # windowed relation, and only the grouped result reaches Ruby.
      def day_expression(table, column)
        zone = self.class.reporting_zone

        Arel.sql(
          case ErrorLog.connection.adapter_name.downcase
          when /postgres/
            "DATE(#{table}.#{column} AT TIME ZONE 'UTC' AT TIME ZONE #{ErrorLog.connection.quote(zone.tzinfo.name)})"
          when /mysql|trilogy/
            # Requires the host's MySQL to have its time-zone tables loaded
            # (mysql_tzinfo_to_sql). Documented in the upgrade notes.
            "DATE(CONVERT_TZ(#{table}.#{column}, '+00:00', #{ErrorLog.connection.quote(zone.formatted_offset)}))"
          else
            # SQLite: no tz database. Bucketing happens in Ruby (see
            # group_by_local_day), so the SQL key is the raw timestamp.
            "#{table}.#{column}"
          end
        )
      end

      # True when the adapter cannot convert zones itself and Ruby must.
      def ruby_side_day_bucketing?
        !ErrorLog.connection.adapter_name.downcase.match?(/postgres|mysql|trilogy/)
      end

      # Collapse a { timestamp => count } result into { Date => count } using
      # the zone's offset AT EACH instant -- which is what makes a DST-spanning
      # window correct.
      def group_by_local_day(rows)
        zone = self.class.reporting_zone
        totals = Hash.new(0)
        rows.each do |key, value|
          time = to_time(key)
          next unless time

          totals[time.in_time_zone(zone).to_date] += value
        end
        totals
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
