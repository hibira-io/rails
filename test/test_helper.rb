# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["HIBIRA_APP_ID"] = "1"
ENV["HIBIRA_APP_KEY"] = "test-key"
ENV["HIBIRA_APP_SECRET"] = "test-secret"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "active_job/railtie"
require "turbo-rails"
require "hibira-rails"
require "minitest/autorun"
require "webmock/minitest"

class Dummy < Rails::Application
  config.root = File.expand_path("dummy", __dir__)
  config.eager_load = false
  config.secret_key_base = "a" * 64
  config.hosts.clear
  config.logger = Logger.new(nil)
  config.active_job.queue_adapter = :inline
  config.action_cable.cable = { "adapter" => "test" }
  config.action_controller.allow_forgery_protection = false
end

class ApplicationController < ActionController::Base
  attr_accessor :current_user

  before_action { self.current_user = request.headers["X-Test-User"]&.then { |id| User.new(id.to_i, "User #{id}") } }
end

User = Struct.new(:id, :name)

Rails.application.initialize!
module HibiraTestHelpers
  EVENTS_URL = "https://ws.hibira.io/apps/1/events"

  def setup
    super
    @previous_config = Hibira.instance_variable_get(:@config)
    Hibira.instance_variable_set(:@config, nil)
    Hibira.config.turbo = true
    Hibira.reset!
    Hibira.webhook_handlers.clear
  end

  def teardown
    Hibira.instance_variable_set(:@config, @previous_config)
    Hibira.reset!
    super
  end

  # Stubs the REST API's trigger endpoint and returns the list that collects
  # each triggered event. Answers with the given statuses in turn.
  def stub_events(*statuses)
    events = []
    statuses = [200] if statuses.empty?
    stub_request(:post, %r{\Ahttps://ws\.hibira\.io/apps/1/events}).to_return do |request|
      events << JSON.parse(request.body)
      status = statuses.length > 1 ? statuses.shift : statuses.first
      { status: status, body: "{}" }
    end
    events
  end
end
