# frozen_string_literal: true

module Hibira
  # Settings for Hibira. Each one falls back to an environment variable and
  # then to `hibira:` in Rails credentials, so an app that sets HIBIRA_APP_ID,
  # HIBIRA_APP_KEY and HIBIRA_APP_SECRET needs no initializer at all.
  class Configuration
    # The app ID, key and secret from your app page on https://hibira.io.
    attr_writer :app_id, :key, :secret

    # The WebSocket host shown on the app page: ws.hibira.io for the default
    # cluster, or ws-<cluster>.hibira.io for apps in another region. The
    # REST API is served on the same host.
    attr_writer :host, :port, :use_tls

    # Send Turbo Stream broadcasts (broadcasts_to, broadcast_append_to,
    # broadcasts_refreshes, ...) through Hibira instead of Action Cable, and
    # make turbo_stream_from subscribe through Hibira. The default, :auto,
    # does so whenever the credentials are set, except in the test
    # environment, where Turbo's own broadcast assertions keep working on
    # Action Cable. true forces it on, false off.
    attr_accessor :turbo

    # What to do when a Turbo Stream broadcast is larger than the app's event
    # size limit (Hibira answers 413): :refresh sends a Turbo 8 page refresh
    # instead, :log logs and drops it, :raise raises Hibira::PayloadTooLarge.
    attr_accessor :oversize

    # Called by the channel auth endpoint (POST /hibira/auth) for private-
    # and presence- channels that are not Turbo streams. Receives the channel
    # name and the controller (for current_user, session, params). Return
    # false or nil to refuse, true to allow a private channel, or a hash such
    # as { user_id: 1, user_info: { name: "Aiko" } } for a presence channel.
    attr_accessor :authorize_channel

    # Push notifications: from the app page → Push notifications.
    attr_writer :push_instance_id, :push_secret_key, :push_endpoint

    # Resolves the signed-in user's push user ID for GET /hibira/push/token
    # (setUserId in the web, Android and iOS SDKs). Receives the controller;
    # return nil when nobody is signed in. Defaults to the ID of current_user
    # (Devise and most auth gems) or Current.user (the Rails 8 generator).
    attr_accessor :push_user_id

    # The controller the channel auth and push token endpoints inherit from,
    # for current_user and your sign-in filters. Defaults to
    # "ApplicationController".
    attr_accessor :parent_controller

    # Extra options passed to Pusher::Client.new (timeouts, http_proxy, ...).
    attr_accessor :client_options

    # The routes for Turbo and channel auth, webhooks and push tokens are drawn
    # under /hibira. Set draw_routes to false to draw your own.
    attr_accessor :draw_routes, :route_prefix

    def initialize
      @turbo = :auto
      @oversize = :refresh
      @client_options = {}
      @parent_controller = "ApplicationController"
      @draw_routes = true
      @route_prefix = "hibira"
      @push_user_id = lambda do |controller|
        user = if controller.respond_to?(:current_user, true)
                 controller.send(:current_user)
               elsif defined?(::Current) && ::Current.respond_to?(:user)
                 ::Current.user
               end
        user&.id
      end
    end

    def app_id = setting(:@app_id, "HIBIRA_APP_ID", :app_id)
    def key = setting(:@key, "HIBIRA_APP_KEY", :key)
    def secret = setting(:@secret, "HIBIRA_APP_SECRET", :secret)
    def host = setting(:@host, "HIBIRA_HOST", :host) || "ws.hibira.io"
    def port = Integer(setting(:@port, "HIBIRA_PORT", :port) || (use_tls ? 443 : 80))

    def use_tls
      value = setting(:@use_tls, "HIBIRA_USE_TLS", :use_tls)
      value.nil? || !%w[false 0 no off].include?(value.to_s.downcase)
    end

    def push_instance_id = setting(:@push_instance_id, "HIBIRA_PUSH_INSTANCE_ID", :push_instance_id)
    def push_secret_key = setting(:@push_secret_key, "HIBIRA_PUSH_SECRET_KEY", :push_secret_key)

    def push_endpoint
      setting(:@push_endpoint, "HIBIRA_PUSH_ENDPOINT", :push_endpoint) || "https://#{host}"
    end

    # Whether Turbo Streams go through Hibira right now (see #turbo).
    def turbo?
      return turbo == true unless turbo == :auto

      configured? && !(defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.test?)
    end

    # True when the app ID, key and secret are all set.
    def configured?
      [app_id, key, secret].none? { |v| v.nil? || v.to_s.empty? }
    end

    def push_configured?
      [push_instance_id, push_secret_key].none? { |v| v.nil? || v.to_s.empty? }
    end

    # Names of the realtime settings that are still blank.
    def missing
      { "HIBIRA_APP_ID" => app_id, "HIBIRA_APP_KEY" => key, "HIBIRA_APP_SECRET" => secret }
        .select { |_, v| v.nil? || v.to_s.empty? }.keys
    end

    private

    def setting(ivar, env, credential)
      value = instance_variable_get(ivar)
      return value unless value.nil?

      value = ENV[env]
      return value unless value.nil? || value.empty?

      credentials&.dig(credential)&.then { |v| v.to_s.empty? ? nil : v }
    end

    def credentials
      return unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application

      ::Rails.application.credentials.hibira
    rescue StandardError
      nil
    end
  end
end
