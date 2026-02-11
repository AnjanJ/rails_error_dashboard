# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Classification methods for statistical values
    #
    # No database access — accepts values, returns classification symbols.
    # Groups related threshold-based classification logic in one place.
    #
    # @example
    #   StatisticalClassifier.correlation_strength(0.85) # => :strong
    #   StatisticalClassifier.trend_direction(25.0)      # => :increasing_significantly
    #   StatisticalClassifier.spike_severity(6.0)        # => :high
    class StatisticalClassifier
      # Classify correlation coefficient into strength categories
      # @param correlation [Float] Pearson correlation coefficient (-1.0 to 1.0)
      # @return [Symbol] :strong, :moderate, or :weak
      def self.correlation_strength(correlation)
        abs_corr = correlation.abs
        if abs_corr >= 0.8
          :strong
        elsif abs_corr >= 0.5
          :moderate
        else
          :weak
        end
      end

      # Classify percentage change into trend direction
      # @param change_percentage [Float] Percentage change between periods
      # @return [Symbol] :increasing_significantly, :increasing, :stable,
      #   :decreasing, or :decreasing_significantly
      def self.trend_direction(change_percentage)
        if change_percentage > 20
          :increasing_significantly
        elsif change_percentage > 5
          :increasing
        elsif change_percentage < -20
          :decreasing_significantly
        elsif change_percentage < -5
          :decreasing
        else
          :stable
        end
      end

      # Classify error spike severity based on multiplier over average
      # @param multiplier [Float] Ratio of current count to average
      # @return [Symbol] :normal, :elevated, :high, or :critical
      def self.spike_severity(multiplier)
        case multiplier
        when 0...2
          :normal
        when 2...5
          :elevated
        when 5...10
          :high
        else
          :critical
        end
      end
    end
  end
end
