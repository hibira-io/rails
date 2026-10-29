# frozen_string_literal: true

require "json"
require "openssl"
require "active_support/security_utils"

module Hibira
  # A webhook post from Hibira. X-Pusher-Signature is the hex HMAC-SHA256 of
  # the body made with the app's current secret. While a rotated-out secret
  # is in its grace period, X-Hibira-Previous-Signature carries the same HMAC
  # made with the old one, so an app that still has the old secret keeps
  # accepting webhooks until it is redeployed.
  class Webhook
    SIGNATURE_HEADERS = %w[HTTP_X_PUSHER_SIGNATURE HTTP_X_HIBIRA_PREVIOUS_SIGNATURE].freeze

    attr_reader :body

    def initialize(env, key: Hibira.config.key, secret: Hibira.config.secret)
      @env = env
      @key = key.to_s
      @secret = secret.to_s
      input = env["rack.input"]
      input.rewind if input.respond_to?(:rewind)
      @body = input ? input.read.to_s : ""
      input.rewind if input.respond_to?(:rewind)
    end

    def valid?
      return false if @key.empty? || @secret.empty?
      return false unless secure_compare(@key, @env["HTTP_X_PUSHER_KEY"].to_s)

      expected = OpenSSL::HMAC.hexdigest("SHA256", @secret, body)
      SIGNATURE_HEADERS.any? { |h| secure_compare(expected, @env[h].to_s) }
    end

    def payload
      @payload ||= JSON.parse(body)
    end

    def events
      Array(payload["events"]).select { |e| e.is_a?(Hash) && e["name"].is_a?(String) }
    end

    def time_ms
      payload["time_ms"].to_i
    end

    private

    def secure_compare(a, b)
      a.bytesize == b.bytesize && ActiveSupport::SecurityUtils.secure_compare(a, b)
    end
  end
end
