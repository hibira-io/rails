# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  include HibiraTestHelpers

  test "reads the environment" do
    config = Hibira::Configuration.new

    assert_equal "1", config.app_id
    assert_equal "test-key", config.key
    assert_equal "ws.hibira.io", config.host
    assert_equal 443, config.port
    assert config.use_tls
    assert config.configured?
  end

  test "settings win over the environment" do
    config = Hibira::Configuration.new
    config.host = "ws-tyo.hibira.io"
    config.use_tls = false

    assert_equal "ws-tyo.hibira.io", config.host
    assert_equal 80, config.port
    assert_equal "https://ws-tyo.hibira.io", config.push_endpoint
  end

  test "falls back to credentials" do
    config = Hibira::Configuration.new
    config.define_singleton_method(:credentials) { { push_instance_id: "from-credentials" } }

    assert_equal "from-credentials", config.push_instance_id
  end

  test "lists missing settings and raises on use" do
    Hibira.configure { |c| c.secret = "" }
    Hibira.config.instance_variable_set(:@secret, nil)
    with_env("HIBIRA_APP_SECRET" => nil) do
      assert_equal ["HIBIRA_APP_SECRET"], Hibira.config.missing
      error = assert_raises(Hibira::MissingCredentials) { Hibira.client }
      assert_includes error.message, "HIBIRA_APP_SECRET"
    end
  end

  test "points the client at Hibira" do
    client = Hibira.client

    assert_equal "ws.hibira.io", client.host
    assert_equal 443, client.port
    assert_equal "https", client.scheme
  end

  test "check reports credentials accepted" do
    stub_request(:get, %r{\Ahttps://ws\.hibira\.io/apps/1/channels}).to_return(status: 200, body: '{"channels":{}}')

    ok, lines = Hibira::Check.run

    assert ok
    assert_includes lines.join("\n"), "Credentials accepted"
  end

  test "check reports refused credentials" do
    stub_request(:get, %r{\Ahttps://ws\.hibira\.io/apps/1/channels}).to_return(status: 401, body: "Invalid signature")

    ok, lines = Hibira::Check.run

    refute ok
    assert_includes lines.join("\n"), "refused"
  end

  private

  def with_env(values)
    old = values.keys.to_h { |k| [k, ENV[k]] }
    values.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
