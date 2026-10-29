# frozen_string_literal: true

module Hibira
  # Checks the settings and credentials, for bin/rails hibira:check.
  module Check
    module_function

    # Returns [ok, lines].
    def run(config = Hibira.config)
      lines = []
      ok = true

      if config.configured?
        lines << "ok    App #{config.app_id} on #{config.host}:#{config.port}"
        begin
          Hibira.client.channels
          lines << "ok    Credentials accepted by the REST API"
        rescue ::Pusher::AuthenticationError
          ok = false
          lines << "fail  The app key or secret was refused. Copy them again from your app page on hibira.io/portal."
        rescue ::Pusher::Error => e
          ok = false
          lines << "fail  Could not reach #{config.host}: #{e.message}"
        end
      else
        ok = false
        lines << "fail  Missing #{config.missing.join(', ')} (environment or credentials hibira:)"
      end

      lines << if config.turbo?
                 "ok    Turbo Streams go through Hibira"
               else
                 "info  Turbo Streams use Action Cable (turbo: #{config.turbo.inspect})"
               end

      lines << if config.push_configured?
                 "ok    Push notifications set up (#{config.push_endpoint})"
               else
                 "info  Push notifications off (set HIBIRA_PUSH_INSTANCE_ID and HIBIRA_PUSH_SECRET_KEY)"
               end

      [ok, lines]
    end
  end
end
