# frozen_string_literal: true

# The template `rails new` applies when benchmark/load/Dockerfile makes the load
# test's app. It adds RED the way the README does, with its installer, and the
# two pages the load test sends traffic to. Everything else stays as the
# generator made it (.shipkit/specs/deploy-shape-benchmark/, REQ-8).

# The RED under test: this checkout, which the Dockerfile copies to /red.
# RED=off runs the same image without it: the gem isn't required, and the
# installer's initializer and mount are skipped. RED's migrations stay in the
# app, and one of them reads RED's models, so prepare a new database with RED on.
append_to_file "Gemfile", <<~RUBY

  gem "rails_error_dashboard", path: "/red", require: ENV["RED"] != "off"
RUBY

# The stack's queue (benchmark/load/stacks.rb): the generator's Solid Queue, or
# Sidekiq in its place, as an app that picks it adds it. The Dockerfile passes
# the QUEUE build arg.
sidekiq = ENV["QUEUE"] == "sidekiq"
gem "sidekiq" if sidekiq

after_bundle do
  # The app's own data: a healthy request reads an order and renders it.
  generate "model", "Order", "number:string:uniq", "total_cents:integer"
  append_to_file "db/seeds.rb", <<~RUBY
    Order.find_or_create_by!(number: "42") { |order| order.total_cents = 4_200 }
  RUBY

  file "app/controllers/orders_controller.rb", <<~'RUBY'
    class OrdersController < ApplicationController
      # A failing request raises this many frames down, as bin/benchmark does,
      # because RED's backtrace handling scales with depth.
      FRAMES = 60

      class ChargeFailed < StandardError; end

      def show
        @order = Order.find_by!(number: params[:number])
      end

      def charge
        charge_from(FRAMES)
      end

      private

      def charge_from(depth)
        depth.zero? ? raise(ChargeFailed, "Order #{params[:number]} could not be charged") : charge_from(depth - 1)
      end
    end
  RUBY

  file "app/views/orders/show.html.erb", <<~'ERB'
    <h1>Order <%= @order.number %></h1>
    <p><%= number_to_currency(@order.total_cents / 100.0) %></p>
  ERB

  route 'get "orders/:number/charge" => "orders#charge"'
  route 'get "orders/:number" => "orders#show"'

  gsub_file! "config/environments/production.rb", "queue_adapter = :solid_queue", "queue_adapter = :sidekiq" if sidekiq

  generate "rails_error_dashboard:install", "--no-interactive"

  # RED=off's switch, in the two places the installer wrote RED into the app.
  # The initializer's goes below its magic comment, which only counts above any
  # code. gsub_file! fails the build if either place has moved.
  gsub_file! "config/initializers/rails_error_dashboard.rb", /\A# frozen_string_literal: true\n/, %(\\0\nreturn if ENV["RED"] == "off"\n)
  gsub_file! "config/routes.rb", %r{^(\s*mount RailsErrorDashboard::Engine => '/red')}, %(\\1 unless ENV["RED"] == "off")
end
