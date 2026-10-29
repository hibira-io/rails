# frozen_string_literal: true

module Hibira
  module StreamsHelper
    # Like turbo_stream_from, but subscribes through Hibira:
    #
    #   <%= hibira_turbo_stream_from @room %>
    #
    # Renders a <hibira-turbo-stream-source> element, which the hibira/turbo
    # JavaScript module turns into a subscription to the stream's private
    # channel. While Turbo goes through Hibira (config.turbo, on whenever the
    # credentials are set), turbo_stream_from renders this too, so existing
    # views need no change.
    def hibira_turbo_stream_from(*streamables, **attributes)
      raise ArgumentError, "streamables can't be blank" unless streamables.any?(&:present?)

      stream_name = ::Turbo::StreamsChannel.send(:stream_name_from, streamables)
      attributes.delete(:channel)
      attributes[:"signed-stream-name"] = ::Turbo::StreamsChannel.signed_stream_name(streamables)
      attributes[:"channel-name"] = Hibira::Turbo.channel_name(stream_name)

      tag.hibira_turbo_stream_source(**hibira_client_attributes, **attributes)
    end

    # Connection settings for the browser, as data attributes. The key is the
    # public app key; the secret never leaves the server.
    def hibira_client_attributes
      config = Hibira.config
      {
        "data-hibira-key": config.key,
        "data-hibira-host": config.host,
        "data-hibira-port": config.port,
        "data-hibira-tls": config.use_tls.to_s,
        "data-hibira-auth-endpoint": hibira_route_path(:hibira_turbo_auth_path, "turbo/auth")
      }
    end

    # Meta tags with the same settings, for your own pusher-js code:
    #
    #   <%= hibira_meta_tags %>
    def hibira_meta_tags
      config = Hibira.config
      safe_join([
        tag.meta(name: "hibira-key", content: config.key),
        tag.meta(name: "hibira-host", content: config.host),
        tag.meta(name: "hibira-port", content: config.port),
        tag.meta(name: "hibira-tls", content: config.use_tls.to_s),
        tag.meta(name: "hibira-auth-endpoint", content: hibira_route_path(:hibira_channel_auth_path, "auth"))
      ], "\n")
    end

    private

    def hibira_route_path(helper, fallback)
      respond_to?(helper) ? public_send(helper) : "/#{Hibira.config.route_prefix}/#{fallback}"
    end
  end

  # Prepended to Turbo::StreamsHelper so turbo_stream_from goes through
  # Hibira while Hibira.config.turbo? is true. A custom Action Cable channel
  # (turbo_stream_from @room, channel: RoomChannel) still uses Action Cable.
  module TurboStreamFrom
    def turbo_stream_from(*streamables, **attributes)
      channel = attributes[:channel]&.to_s
      if Hibira.config.turbo? && (channel.nil? || channel == "Turbo::StreamsChannel")
        hibira_turbo_stream_from(*streamables, **attributes)
      else
        super
      end
    end
  end
end
