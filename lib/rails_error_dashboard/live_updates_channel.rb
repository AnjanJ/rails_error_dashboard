# frozen_string_literal: true

module RailsErrorDashboard
  # The channel the error list subscribes through when live updates are on.
  #
  # Not Turbo::StreamsChannel: that channel accepts any name signed by Turbo's
  # verifier, and those signatures never expire. This one accepts only a token
  # from Services::LiveStreamToken, which expires, and it keeps checking that
  # expiry for as long as the subscription stays open. The messages are still
  # built by turbo-rails' broadcast methods, and the browser still uses its
  # <turbo-cable-stream-source> element, pointed here by its channel attribute.
  #
  # Loaded only when Action Cable is (Engine.load_live_updates_channel), so a
  # host without it never reaches this file, eager loading included.
  class LiveUpdatesChannel < ActionCable::Channel::Base
    private

    # Private, as in ActionCable::Channel::Base: Action Cable lets a client call
    # any public method of a channel as an action, and a second run of this one
    # would leak a pubsub subscription.
    def subscribed
      token = Services::LiveStreamToken.verify(params[:signed_stream_name])
      return reject unless token && RailsErrorDashboard.configuration.enable_live_updates

      @expires_at = token[:expires_at]
      stream_from token[:stream], method(:relay), coder: ActiveSupport::JSON
    end

    # Runs for every broadcast on the stream. An open socket keeps its
    # subscription after the token expires; from then on it gets nothing.
    def relay(message)
      if Time.now.to_i < @expires_at
        transmit message
      else
        stop_all_streams
      end
    end
  end
end
