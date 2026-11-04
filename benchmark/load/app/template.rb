# frozen_string_literal: true

# The template `rails new` applies when benchmark/load/Dockerfile makes the load
# test's app. It adds RED the way the README does, with its installer, and the
# two pages the load test sends traffic to. Everything else stays as the
# generator made it (.shipkit/specs/deploy-shape-benchmark/, REQ-8).

# The RED under test: this checkout, which the Dockerfile copies to /red.
gem "rails_error_dashboard", path: "/red"

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

  generate "rails_error_dashboard:install", "--no-interactive"
end
