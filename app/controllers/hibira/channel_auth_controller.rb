# frozen_string_literal: true

module Hibira
  # Signs subscriptions to your own private- and presence- channels through
  # Hibira.config.authorize_channel. Inherits from your ApplicationController
  # (Hibira.config.parent_controller), so current_user, the session and CSRF
  # protection work as in the rest of your app.
  class ChannelAuthController < Hibira.config.parent_controller.constantize
    def create
      channel_name = params[:channel_name].to_s
      socket_id = params[:socket_id].to_s
      authorize = Hibira.config.authorize_channel

      return head(:forbidden) if authorize.nil? || Hibira::Turbo.turbo_channel?(channel_name)
      return head(:forbidden) unless channel_name.start_with?("private-", "presence-")

      result = authorize.call(channel_name, self)
      return head(:forbidden) unless result

      if channel_name.start_with?("presence-")
        return head(:forbidden) unless result.is_a?(Hash) && result.with_indifferent_access[:user_id].present?

        render json: Hibira.client.authenticate(channel_name, socket_id, presence_data(result))
      else
        render json: Hibira.client.authenticate(channel_name, socket_id)
      end
    rescue ::Pusher::Error
      head :unprocessable_entity
    end

    private

    def presence_data(result)
      result = result.with_indifferent_access
      { user_id: result[:user_id].to_s, user_info: result[:user_info] || {} }
    end
  end
end
