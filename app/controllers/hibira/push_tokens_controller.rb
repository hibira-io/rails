# frozen_string_literal: true

module Hibira
  # Returns a Beams user token for the signed-in user, for setUserId in the
  # web, Android and iOS SDKs, at GET /hibira/push/token. The SDKs pass
  # ?user_id=, which must be the signed-in user's push user ID
  # (Hibira.config.push_user_id).
  class PushTokensController < Hibira.config.parent_controller.constantize
    def show
      user_id = Hibira.config.push_user_id.call(self)&.to_s
      return head(:unauthorized) if user_id.blank?
      return head(:unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(user_id, params[:user_id].to_s)

      render json: Hibira.push.generate_token(user: user_id)
    end
  end
end
