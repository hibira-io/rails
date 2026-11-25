# frozen_string_literal: true

require "openssl"

module Hibira
  # Hibira Live Chat (https://chat.hibira.io) on Rails pages:
  #
  #   <%= hibira_live_chat %>
  #
  # With config.livechat_identity_secret set (Live Chat › Settings › Widget ›
  # Verified visitors), the signed-in user chats as themselves: their ID is
  # signed with the secret, so the inbox shows their name and email and
  # nobody can pretend to be them.
  module LiveChat
    SCRIPT_URL = "https://chat.hibira.io/w/v1.js"

    module_function

    # hex(HMAC-SHA256(identity secret, user ID)): the widget's data-user-hash.
    def user_hash(identity_secret, user_id)
      raise ArgumentError, "identity_secret is required" if identity_secret.to_s.empty?

      OpenSSL::HMAC.hexdigest("SHA256", identity_secret.to_s, user_id.to_s)
    end

    # The verified-visitor fields for a user ({ id:, hash:, name:, email: }),
    # or nil without a user or an identity secret. Hand it to an SPA and call
    # HibiraLiveChat.identify(it).
    def identity(user)
      secret = Hibira.config.livechat_identity_secret
      return if user.nil? || secret.to_s.empty?

      about = Hibira.config.livechat_describe_user.call(user) || {}
      id = about[:id]
      return if id.nil? || id.to_s.empty?

      { id: id.to_s, hash: user_hash(secret, id), name: about[:name].presence&.to_s,
        email: about[:email].presence&.to_s }.compact
    end
  end

  module LiveChatHelper
    # The Live Chat widget's script tag; empty without a workspace. Options:
    # color: "#0a7", lang: "ja", launcher: false, workspace: "...".
    def hibira_live_chat(workspace: nil, color: nil, lang: nil, launcher: true, nonce: nil)
      ws = workspace.presence || Hibira.config.livechat_workspace
      return "".html_safe if ws.to_s.empty?

      data = { workspace: ws }
      data[:color] = color if color.present?
      data[:lang] = lang if lang.present?
      data[:launcher] = "none" unless launcher
      if (who = Hibira::LiveChat.identity(hibira_live_chat_user))
        data[:user_id] = who[:id]
        data[:user_hash] = who[:hash]
        data[:user_name] = who[:name] if who[:name]
        data[:user_email] = who[:email] if who[:email]
      end
      # content_tag dasherizes the data keys (user_hash → data-user-hash).
      content_tag(:script, "", src: Hibira::LiveChat::SCRIPT_URL, async: true, nonce: nonce, data: data)
    end

    private

    def hibira_live_chat_user
      controller = respond_to?(:controller) ? self.controller : nil
      return unless controller

      Hibira.config.livechat_user.call(controller)
    end
  end
end
