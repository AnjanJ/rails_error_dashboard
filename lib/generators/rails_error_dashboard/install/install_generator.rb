# frozen_string_literal: true

module RailsErrorDashboard
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc "Installs Rails Error Dashboard and generates the necessary files"

      def create_initializer_file
        template "initializer.rb", "config/initializers/rails_error_dashboard.rb"
      end

      def copy_migrations
        rake "rails_error_dashboard:install:migrations"
      end

      def add_route
        route "mount RailsErrorDashboard::Engine => '/error_dashboard'"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
