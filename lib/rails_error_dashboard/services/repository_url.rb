# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # The one normal form of a configured repository URL, shared by the View
    # Source links and the issue tracker: no surrounding whitespace, no trailing
    # slashes, no ".git". The slashes go first, or ".git/" keeps its ".git".
    module RepositoryUrl
      # @param url [String, nil]
      # @return [String, nil]
      def self.normalize(url)
        return nil if url.nil?

        url.to_s.strip.sub(%r{/+\z}, "").delete_suffix(".git").sub(%r{/+\z}, "")
      end
    end
  end
end
