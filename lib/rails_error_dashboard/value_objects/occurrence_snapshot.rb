# frozen_string_literal: true

module RailsErrorDashboard
  module ValueObjects
    # The error as it looked at one occurrence: a read-only copy of the error
    # row whose breadcrumbs, system health and variables are that occurrence's
    # stored context. Every other field keeps the row's latest value.
    #
    # A real ErrorLog rather than a delegator, so every way a card reads a
    # piece sees the occurrence's value: the instance-variables card goes
    # through read_attribute and error.class.column_names, because
    # Object#instance_variables shadows the attribute reader.
    module OccurrenceSnapshot
      # @param error [ErrorLog] the error the context belongs to
      # @param context [ErrorOccurrenceContext] one of its occurrences' contexts
      # @return [ErrorLog] read-only; a piece the occurrence did not capture is nil
      def self.build(error, context)
        pieces = Commands::RecordOccurrenceContext::PIECES.to_h { |piece| [ piece.to_s, context.read_attribute(piece) ] }
        error.class.instantiate(error.attributes_before_type_cast.merge(pieces)).tap(&:readonly!)
      end
    end
  end
end
