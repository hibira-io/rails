# frozen_string_literal: true

require "digest"

module Hibira
  # Turbo Streams over Hibira. Each Turbo stream name maps to one private
  # channel, so a browser can only subscribe with the signed stream name that
  # turbo_stream_from rendered for it, the same rule Action Cable applies.
  module Turbo
    EVENT = "turbo-stream"
    CHANNEL_PREFIX = "private-turbo-"
    REFRESH = '<turbo-stream action="refresh"></turbo-stream>'

    class << self
      # Stream names hold characters channel names cannot ("gid://app/Room/1"),
      # so the channel is named after a digest of the stream name.
      def channel_name(stream_name)
        "#{CHANNEL_PREFIX}#{Digest::SHA256.hexdigest(stream_name.to_s)}"
      end

      def turbo_channel?(channel_name)
        channel_name.to_s.start_with?(CHANNEL_PREFIX)
      end

      def broadcast(stream_name, content)
        Hibira.trigger(channel_name(stream_name), EVENT, content.to_s)
      rescue ::Pusher::Error => e
        raise unless e.message.include?("Payload Too Large")

        oversized(stream_name, content, e)
      end

      private

      def oversized(stream_name, content, error)
        message = "[Hibira] Turbo Stream for #{stream_name.inspect} is #{content.to_s.bytesize} bytes, " \
                  "over the app's event size limit"

        case Hibira.config.oversize
        when :raise
          raise PayloadTooLarge, message
        when :refresh
          if content.to_s.include?('action="refresh"')
            logger&.warn("#{message}; dropped")
          else
            logger&.warn("#{message}; sent a page refresh instead")
            Hibira.trigger(channel_name(stream_name), EVENT, REFRESH)
          end
        else
          logger&.warn("#{message}; dropped")
        end
        nil
      end

      def logger
        defined?(::Rails) && ::Rails.respond_to?(:logger) ? ::Rails.logger : nil
      end
    end

    # Prepended to Turbo::StreamsChannel's singleton class. Every Turbo
    # broadcast (broadcast_*_to, broadcasts_to, broadcasts_refreshes and the
    # _later jobs) ends in broadcast_stream_to, so this one override sends all
    # of them to Hibira.
    module Broadcasts
      def broadcast_stream_to(*streamables, content:)
        return super unless Hibira.config.turbo?

        streamables = streamables.flatten.compact_blank
        return if streamables.empty?

        Hibira::Turbo.broadcast(stream_name_from(streamables), content)
      end
    end
  end
end
