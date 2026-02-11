# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Calculate Pearson correlation coefficient between two series
    #
    # No database access — accepts arrays, returns a correlation value.
    # Used by ErrorCorrelation query to find time-correlated error types.
    #
    # @example
    #   PearsonCorrelation.call([1, 2, 3], [1, 2, 3])
    #   # => 1.0 (perfect positive correlation)
    class PearsonCorrelation
      # @param series_a [Array<Numeric>] First data series
      # @param series_b [Array<Numeric>] Second data series
      # @return [Float] Correlation coefficient between -1.0 and 1.0
      def self.call(series_a, series_b)
        return 0.0 if series_a.empty? || series_b.empty?
        return 0.0 if series_a.sum.zero? || series_b.sum.zero?

        n = series_a.length
        return 0.0 if n.zero?

        mean_a = series_a.sum.to_f / n
        mean_b = series_b.sum.to_f / n

        covariance = 0.0
        std_a = 0.0
        std_b = 0.0

        n.times do |i|
          diff_a = series_a[i] - mean_a
          diff_b = series_b[i] - mean_b
          covariance += diff_a * diff_b
          std_a += diff_a**2
          std_b += diff_b**2
        end

        denominator = Math.sqrt(std_a * std_b)
        return 0.0 if denominator.zero?

        (covariance / denominator).round(3)
      end
    end
  end
end
