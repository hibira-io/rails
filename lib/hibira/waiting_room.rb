# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "rack"
require "active_support/concern"

module Hibira
  # Waiting rooms: send visitors to the Hibira queue, let them in with a pass.
  #
  # In a controller:
  #
  #   class DropsController < ApplicationController
  #     waiting_room "presale", only: :show
  #
  #     def show
  #       hibira_pass.number # also ticket_id, expires_at
  #     end
  #   end
  #
  # Or for path prefixes in any Rack app:
  #
  #   config.middleware.use Hibira::WaitingRoom::Middleware, "/drop" => "presale"
  #
  # A visitor without a valid pass is redirected to the hosted waiting page
  # (non-GET requests get a 403). When it's their turn the page sends them
  # back with ?hibira_pass=..., which is checked, stored in an HttpOnly cookie
  # (hibira_wr_<room>) and removed from the URL.
  module WaitingRoom
    PURPOSE = "hibira-waitroom-pass."
    PARAM = "hibira_pass"
    ENV_KEY = "hibira.pass"

    Pass = Struct.new(:app_id, :room, :number, :ticket_id, :issued_at, :expires_at, keyword_init: true)

    class << self
      # Returns the pass's claims, or nil when it is missing, forged, expired,
      # or for another room or app. secret may be an array during a rotation.
      def verify_pass(token, secret: Hibira.config.secret, room: nil, app_id: nil, now: Time.now.to_f)
        return unless token.is_a?(String) && token.length <= 1024 && token.count(".") == 1

        payload, sig = token.split(".", 2)
        sig = decode(sig)
        return if payload.empty? || sig.nil? || sig.bytesize != 32

        message = PURPOSE + payload
        valid = Array(secret).compact.reject(&:empty?).any? do |s|
          Rack::Utils.secure_compare(OpenSSL::HMAC.digest("SHA256", s, message), sig)
        end
        return unless valid

        claims = JSON.parse(decode(payload).to_s) rescue nil
        return unless claims.is_a?(Hash) && claims["v"] == 1 && claims["exp"].is_a?(Numeric)
        return if now >= claims["exp"]
        return if room && claims["room"] != room
        return if app_id && claims["app"] != app_id.to_s

        Pass.new(app_id: claims["app"], room: claims["room"], number: claims["n"], ticket_id: claims["tid"],
                 issued_at: claims["iat"], expires_at: claims["exp"].to_i)
      end

      # The hosted waiting page address for a room.
      def url(room, return_url = nil, app_key: Hibira.config.key, host: nil, lang: nil)
        base = "#{(host || default_host).chomp('/')}/wait/#{escape(app_key)}/#{escape(room)}"
        query = { "return" => return_url, "lang" => lang }.compact
        query.empty? ? base : "#{base}?#{Rack::Utils.build_query(query)}"
      end

      # Checks a Rack request. Returns nil to let it through (the claims are in
      # env["hibira.pass"]), or the Rack response to send instead.
      def check(env, room, secret: nil, app_key: nil, host: nil, lang: nil, cookie_name: nil)
        secret ||= Hibira.config.secret
        raise MissingCredentials, "Waiting rooms need HIBIRA_APP_SECRET" if Array(secret).compact.empty?

        request = Rack::Request.new(env)
        name = cookie_name || "hibira_wr_#{room}"
        app_id = Hibira.config.app_id
        clean = url_without_pass(request)

        fresh = request.GET[PARAM]
        if fresh && (claims = verify_pass(fresh, secret: secret, room: room, app_id: app_id))
          headers = { "location" => clean, "cache-control" => "no-store" }
          Rack::Utils.set_cookie_header!(headers, name,
                                         value: fresh, path: "/", httponly: true, same_site: :lax,
                                         secure: request.ssl?, max_age: [claims.expires_at - Time.now.to_i, 0].max)
          return [302, headers, []]
        end

        claims = verify_pass(request.cookies[name], secret: secret, room: room, app_id: app_id)
        if claims
          env[ENV_KEY] = claims
          return
        end

        if %w[GET HEAD].include?(request.request_method)
          location = url(room, clean, app_key: app_key || Hibira.config.key, host: host, lang: lang)
          [302, { "location" => location, "cache-control" => "no-store" }, []]
        else
          body = JSON.generate(error: "waiting_room", message: "join the waiting room first")
          [403, { "content-type" => "application/json", "cache-control" => "no-store" }, [body]]
        end
      end

      private

      def default_host
        c = Hibira.config
        scheme = c.use_tls ? "https" : "http"
        port = c.port == (c.use_tls ? 443 : 80) ? "" : ":#{c.port}"
        "#{scheme}://#{c.host}#{port}"
      end

      def url_without_pass(request)
        query = Rack::Utils.parse_query(request.query_string).except(PARAM)
        base = request.base_url + request.path
        query.empty? ? base : "#{base}?#{Rack::Utils.build_query(query)}"
      end

      def escape(value) = Rack::Utils.escape_path(value.to_s)

      def decode(value)
        return unless value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]+\z/)

        Base64.urlsafe_decode64(value + ("=" * (-value.length % 4)))
      rescue ArgumentError
        nil
      end
    end

    # Rack middleware protecting path prefixes: { "/drop" => "presale" }. The
    # longest matching prefix wins. options: secret, app_key, host, lang.
    class Middleware
      def initialize(app, rooms, options = {})
        @app = app
        @rooms = rooms.transform_keys(&:to_s).sort_by { |prefix, _| -prefix.length }
        @options = options
      end

      def call(env)
        path = env["PATH_INFO"].to_s
        _, room = @rooms.find { |prefix, _| path == prefix || path.start_with?(prefix.end_with?("/") ? prefix : "#{prefix}/") }
        (room && WaitingRoom.check(env, room, **@options)) || @app.call(env)
      end
    end

    # Adds `waiting_room "room", only: ...` to controllers and `hibira_pass`.
    module Controller
      extend ActiveSupport::Concern

      class_methods do
        def waiting_room(room, secret: nil, app_key: nil, host: nil, lang: nil, cookie_name: nil, **filter)
          options = { secret: secret, app_key: app_key, host: host, lang: lang, cookie_name: cookie_name }
          before_action(**filter) do
            status, headers, body = WaitingRoom.check(request.env, room, **options)
            if status
              headers.each { |k, v| response.set_header(k, v) }
              self.status = status
              self.response_body = body
            end
          end
        end
      end

      def hibira_pass = request.env[ENV_KEY]
    end
  end
end
