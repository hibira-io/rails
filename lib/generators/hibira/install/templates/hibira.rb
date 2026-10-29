# frozen_string_literal: true

# Hibira reads HIBIRA_APP_ID, HIBIRA_APP_KEY, HIBIRA_APP_SECRET and HIBIRA_HOST
# from the environment, then hibira: in your credentials. Anything set here
# wins. See https://github.com/hibira-io/rails for every option.
Hibira.configure do |config|
  # Turbo Streams go through Hibira whenever the credentials are set (except
  # in tests). Set true or false to force it.
  # config.turbo = :auto

  # A broadcast over your plan's event size limit is sent as a Turbo page
  # refresh instead. Or :log to drop it, :raise to raise.
  # config.oversize = :refresh

  # Authorize your own private- and presence- channels (POST /hibira/auth).
  # config.authorize_channel = lambda do |channel, controller|
  #   user = controller.send(:current_user)
  #   case channel
  #   when /\Aprivate-user\.(\d+)\z/ then user&.id == $1.to_i
  #   when /\Apresence-room\.(\d+)\z/ then user && { user_id: user.id, user_info: { name: user.name } }
  #   end
  # end
end

# Hibira.on_webhook("channel_vacated") do |event|
#   Rails.logger.info "#{event['channel']} is empty"
# end
