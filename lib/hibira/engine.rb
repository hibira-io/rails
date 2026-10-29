# frozen_string_literal: true

require "rails/engine"
# Turbo::StreamsChannel subclasses ActionCable::Channel::Base, so the
# constants must load even in apps generated with --skip-action-cable. No
# Action Cable server is mounted or needed.
require "action_cable"

module Hibira
  class Engine < ::Rails::Engine
    initializer "hibira.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join("app/javascript")
        app.config.assets.precompile += %w[hibira/turbo.js] if app.config.assets.respond_to?(:precompile)
      end
    end

    initializer "hibira.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << root.join("config/importmap.rb")
        app.config.importmap.cache_sweepers << root.join("app/javascript")
      end
    end

    initializer "hibira.helpers" do
      ActiveSupport.on_load(:action_view) do
        include Hibira::StreamsHelper
      end
    end

    # The Hibira routes are drawn straight into the app's routes (like Active
    # Storage's), under Hibira.config.route_prefix.
    initializer "hibira.routes" do |app|
      app.routes.prepend do
        next unless Hibira.config.draw_routes

        scope Hibira.config.route_prefix, module: "hibira", as: "hibira" do
          post "turbo/auth" => "turbo_auth#create", as: :turbo_auth
          post "auth" => "channel_auth#create", as: :channel_auth
          post "webhooks" => "webhooks#create", as: :webhooks
          get "push/token" => "push_tokens#show", as: :push_token
        end
      end
    end

    config.to_prepare do
      if defined?(::Turbo::StreamsChannel)
        singleton = ::Turbo::StreamsChannel.singleton_class
        singleton.prepend(Hibira::Turbo::Broadcasts) unless singleton < Hibira::Turbo::Broadcasts
      end
      if defined?(::Turbo::StreamsHelper) && !(::Turbo::StreamsHelper < Hibira::TurboStreamFrom)
        ::Turbo::StreamsHelper.prepend(Hibira::TurboStreamFrom)
      end
    end
  end
end
