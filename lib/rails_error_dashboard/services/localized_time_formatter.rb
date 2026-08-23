# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # strftime with the word-producing directives resolved from RED's own
    # dictionary.
    #
    # WHY THIS EXISTS
    #
    # Ruby's strftime is not locale-aware: %B is "August" whatever RED's locale
    # is. On the dashboard that does not matter, because a timestamp is
    # rendered as a <span data-format> and the browser re-renders it through
    # formatDateTime() using the red.js.* month/day/meridian vocabulary P3-T2
    # added. Anywhere there is no browser — email (P4-T2), Slack and Discord
    # payloads (P4-T3) — the server has to do that substitution itself.
    #
    # Sharing one implementation is the point: an email, a Slack message and
    # the dashboard should not disagree about what a date looks like.
    #
    # Takes the locale as an argument rather than reading Current, because
    # every caller runs inside a job where Current is nil or belongs to an
    # unrelated request.
    class LocalizedTimeFormatter
      # The directives whose output is a *word*, and therefore locale-dependent:
      # %B %b (month), %A %a (weekday), %p %P (meridian). Everything else
      # (%Y, %m, %d, %H, %M, %S, %Z …) is digits or a timezone abbreviation and
      # is left to strftime.
      LOCALIZED_DIRECTIVES = /%[BbAaPp]/

      # Stand-in for a localized word while strftime runs. Contains no percent,
      # so strftime cannot read it as a directive, and no space, so it cannot
      # alter the spacing the pattern asked for. The index keeps two
      # occurrences of the same directive independent.
      PLACEHOLDER = "\u0000RED%<index>d\u0000"

      # @param time [Time]
      # @param pattern [String] a strftime pattern
      # @param locale [String]
      # @return [String]
      def self.call(time, pattern:, locale:)
        new(locale).render(time, pattern)
      end

      def initialize(locale)
        @locale = locale
      end

      # Two-pass, via placeholders: substituting a translated month name
      # directly would put arbitrary text into the pattern, and while a French
      # "%A" -> "mardi" is harmless, a translation containing a literal percent
      # sign would corrupt every directive after it. The placeholder carries no
      # percent, so strftime cannot misread it.
      def render(time, pattern)
        replacements = []

        staged = pattern.gsub(LOCALIZED_DIRECTIVES) do |directive|
          word = localized_word(directive, time)
          next directive if word.nil?

          replacements << word
          format(PLACEHOLDER, index: replacements.length - 1)
        end

        rendered = time.strftime(staged)

        replacements.each_with_index do |word, index|
          rendered = rendered.sub(format(PLACEHOLDER, index: index), word)
        end

        rendered
      end

      private

      attr_reader :locale

      # @return [String, nil] nil means "leave it to strftime"
      def localized_word(directive, time)
        case directive
        when "%B" then name_array(:months, 12)[time.month - 1]
        when "%b" then name_array(:months_short, 12)[time.month - 1]
        when "%A" then name_array(:days, 7)[time.wday]
        when "%a" then name_array(:days_short, 7)[time.wday]
        when "%p" then meridian_for(time)
        when "%P" then meridian_for(time)&.downcase
        end
      end

      # I18nStore.subtree returns SYMBOL keys — the backend loads the YAML
      # symbolized. Indexing with a String silently yields nil here, and
      # because a nil array falls back to English the bug looks exactly like
      # "this locale has no translation" rather than like a defect. Caught in
      # P4-T2 by a spec that asserted a translated month name and got English.
      #
      # A locale that translates only some of these must not produce a mix of
      # translated and English names, so the whole array falls back together —
      # the same rule I18nStore.subtree applies for the JS payload.
      def name_array(key, expected_length)
        names = I18nStore.subtree("red.js", locale: locale)[key]
        return names if names.is_a?(Array) && names.length == expected_length

        fallback = I18nStore.subtree("red.js", locale: I18nStore::DEFAULT_LOCALE)[key]
        fallback.is_a?(Array) ? fallback : []
      end

      # A 24-hour locale may legitimately translate these to "", which is why
      # this checks for a String rather than for presence.
      def meridian_for(time)
        meridian = I18nStore.subtree("red.js.meridian", locale: locale)
        value = time.hour >= 12 ? meridian[:pm] : meridian[:am]
        return value if value.is_a?(String)

        time.hour >= 12 ? "PM" : "AM"
      end
    end
  end
end
