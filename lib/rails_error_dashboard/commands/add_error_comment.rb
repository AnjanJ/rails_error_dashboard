# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Add a comment to an error
    # This is a write operation that creates an ErrorComment record
    class AddErrorComment
      def self.call(error_id, author_name:, body:)
        new(error_id, author_name, body).call
      end

      def initialize(error_id, author_name, body)
        @error_id = error_id
        @author_name = author_name
        @body = body
      end

      def call
        error = ErrorLog.find(@error_id)
        error.comments.create!(
          author_name: @author_name,
          body: @body
        )
        error
      end
    end
  end
end
