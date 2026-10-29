# frozen_string_literal: true

module Hibira
  # Receives Hibira webhooks at POST /hibira/webhooks. Add that URL on your
  # app page → Webhooks. Each verified event runs the Hibira.on_webhook
  # handlers for its name and is instrumented as "webhook.hibira".
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    def create
      webhook = Hibira::Webhook.new(request.env)
      return head(:unauthorized) unless webhook.valid?

      events = begin
        webhook.events
      rescue JSON::ParserError
        return head(:bad_request)
      end

      events.each do |event|
        ActiveSupport::Notifications.instrument("webhook.hibira", event: event, time_ms: webhook.time_ms) do
          (Hibira.webhook_handlers[event["name"]] + Hibira.webhook_handlers["*"]).each do |handler|
            handler.call(event)
          end
        end
      end

      head :ok
    end
  end
end
