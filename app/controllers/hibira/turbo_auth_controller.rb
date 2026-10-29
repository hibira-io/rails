# frozen_string_literal: true

module Hibira
  # Signs subscriptions to Turbo stream channels. The signed stream name that
  # turbo_stream_from rendered is the credential, as it is for Action Cable,
  # so this needs no session and no CSRF token.
  class TurboAuthController < ActionController::Base
    skip_forgery_protection

    def create
      stream_name = ::Turbo::StreamsChannel.verified_stream_name(params[:signed_stream_name].to_s)
      channel_name = params[:channel_name].to_s

      if stream_name && channel_name == Hibira::Turbo.channel_name(stream_name)
        render json: Hibira.client.authenticate(channel_name, params[:socket_id].to_s)
      else
        head :forbidden
      end
    rescue ::Pusher::Error
      head :unprocessable_entity
    end
  end
end
