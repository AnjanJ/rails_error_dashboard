module RailsErrorDashboard
  class ApplicationController < ActionController::Base
    include Pagy::Backend

    layout "rails_error_dashboard"

    protect_from_forgery with: :exception

    # Make Pagy helpers available in views
    helper Pagy::Frontend
  end
end
