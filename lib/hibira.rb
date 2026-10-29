# frozen_string_literal: true

require "pusher"
require "hibira/version"
require "hibira/configuration"
require "hibira/webhook"
require "hibira/turbo"
require "hibira/streams_helper"
require "hibira/check"

# Rails integration for Hibira (https://hibira.io): Turbo Streams, private and
# presence channel auth, webhooks and push notifications over the Pusher
# Channels protocol.
module Hibira
  class Error < StandardError; end
  class MissingCredentials < Error; end
  class PayloadTooLarge < Error; end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      reset!
      config
    end

    # The pusher-http-ruby client, pointed at Hibira.
    def client
      @client ||= begin
        unless config.configured?
          raise MissingCredentials, "Hibira is not configured: set #{config.missing.join(', ')} " \
                                    "(run bin/rails hibira:check)"
        end

        ::Pusher::Client.new(
          app_id: config.app_id.to_s,
          key: config.key,
          secret: config.secret,
          host: config.host,
          port: config.port,
          use_tls: config.use_tls,
          **config.client_options
        )
      end
    end

    # Hibira.trigger("orders", "order-shipped", { id: 1024 })
    def trigger(channels, event, data, params = {})
      client.trigger(channels, event, data, params)
    end

    # The Beams-compatible push client, pointed at Hibira. Needs the
    # pusher-push-notifications gem in your Gemfile.
    def push
      begin
        require "pusher/push_notifications"
      rescue LoadError
        raise Error, "Add gem \"pusher-push-notifications\" to your Gemfile to send push notifications"
      end
      raise MissingCredentials, "Set HIBIRA_PUSH_INSTANCE_ID and HIBIRA_PUSH_SECRET_KEY" unless config.push_configured?

      push = ::Pusher::PushNotifications
      push.configure do |c|
        c.instance_id = config.push_instance_id
        c.secret_key = config.push_secret_key
        c.endpoint = config.push_endpoint
      end
      push
    end

    # Runs the block for each verified webhook event with that name ("*" for
    # all). Events are also instrumented as "webhook.hibira".
    #
    #   Hibira.on_webhook("channel_vacated") { |event| Room.close(event["channel"]) }
    def on_webhook(name = "*", &block)
      webhook_handlers[name.to_s] << block
      block
    end

    def webhook_handlers
      @webhook_handlers ||= Hash.new { |h, k| h[k] = [] }
    end

    def reset!
      @client = nil
    end
  end
end

require "hibira/engine" if defined?(Rails::Engine)
