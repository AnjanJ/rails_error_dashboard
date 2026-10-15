# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Calculates similarity scores between errors using multiple algorithms
    #
    # Combines:
    # - Backtrace similarity (Jaccard index on stack frames) - 70% weight
    # - Message similarity (Levenshtein distance) - 30% weight
    #
    # Returns a similarity score from 0.0 (completely different) to 1.0 (identical)
    class SimilarityCalculator
      # Calculate similarity between two errors
      #
      # @param error1 [ErrorLog] First error to compare
      # @param error2 [ErrorLog] Second error to compare
      # @return [Float] Similarity score from 0.0 to 1.0
      def self.call(error1, error2)
        new(error1, error2).calculate
      end

      def initialize(error1, error2)
        @error1 = error1
        @error2 = error2
      end

      def calculate
        # Quick return for same error
        return 1.0 if @error1.id == @error2.id

        # Quick return for different platforms (per user config - same platform only)
        return 0.0 if different_platforms?

        backtrace_score = calculate_backtrace_similarity
        message_score = calculate_message_similarity

        # Weighted combination: backtrace 70%, message 30%
        (backtrace_score * 0.7) + (message_score * 0.3)
      end

      private

      def different_platforms?
        return false if @error1.platform.nil? || @error2.platform.nil?
        @error1.platform != @error2.platform
      end

      # Calculate Jaccard similarity on backtrace frames
      # Jaccard = intersection / union
      def calculate_backtrace_similarity
        frames1 = extract_frames(@error1.backtrace)
        frames2 = extract_frames(@error2.backtrace)

        return 0.0 if frames1.empty? || frames2.empty?

        intersection = (frames1 & frames2).size
        union = (frames1 | frames2).size

        return 0.0 if union.zero?

        intersection.to_f / union
      end

      # Calculate normalized Levenshtein distance on messages
      # Returns 1.0 for identical messages, decreasing as they differ
      def calculate_message_similarity
        msg1 = normalize_message(@error1.message)
        msg2 = normalize_message(@error2.message)

        return 1.0 if msg1 == msg2
        return 0.0 if msg1.empty? || msg2.empty?

        distance = levenshtein_distance(msg1, msg2)
        max_length = [ msg1.length, msg2.length ].max

        return 0.0 if max_length.zero?

        # Convert distance to similarity (1.0 = identical, 0.0 = completely different)
        1.0 - (distance.to_f / max_length)
      end

      # Extract meaningful frames from backtrace
      # "file.rb:123:in `name'" (Ruby 3.3) or "file.rb:123:in 'Class#name'"
      # (Ruby 3.4) => "file.rb:name", via BacktraceProcessor.frame_key
      def extract_frames(backtrace)
        return [] if backtrace.blank?

        lines = backtrace.is_a?(String) ? backtrace.split("\n") : backtrace
        lines.first(20).map { |line| BacktraceProcessor.frame_key(line) }.compact.uniq  # Only consider first 20 frames
      end

      # Normalize message for comparison
      # Already normalized during error logging, but ensure consistency
      def normalize_message(message)
        return "" if message.nil?

        message
          .gsub(/#<\w+:0x[0-9a-f]+>/i, "__OBJ__")   # Object inspections - temp placeholder
          .gsub(/0x[0-9a-f]+/i, "__HEX__")          # Hex addresses - temp placeholder
          .gsub(/"[^"]*"/, '""')                     # Quoted strings to ""
          .gsub(/'[^']*'/, "''")                     # Single quotes to ''
          .downcase                                   # Convert to lowercase
          .gsub(/\d+/, "n")                           # Numbers to n (lowercase)
          .gsub(/__hex__/, "0xhex")                   # Replace placeholder with final value
          .gsub(/__obj__/, "#<obj>")                  # Replace placeholder with final value
          .strip
      end

      # Calculate Levenshtein distance (edit distance) between two strings
      # Classic dynamic programming algorithm
      def levenshtein_distance(str1, str2)
        return str2.length if str1.empty?
        return str1.length if str2.empty?

        # Create matrix
        matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1, 0) }

        # Initialize first row and column
        (0..str1.length).each { |i| matrix[i][0] = i }
        (0..str2.length).each { |j| matrix[0][j] = j }

        # Fill matrix
        (1..str1.length).each do |i|
          (1..str2.length).each do |j|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,      # deletion
              matrix[i][j - 1] + 1,      # insertion
              matrix[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        matrix[str1.length][str2.length]
      end
    end
  end
end
