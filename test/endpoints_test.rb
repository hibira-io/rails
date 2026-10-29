# frozen_string_literal: true

require "test_helper"

class EndpointsTest < ActionDispatch::IntegrationTest
  include HibiraTestHelpers

  SOCKET_ID = "1234.5678"

  def signature(channel, data = nil)
    OpenSSL::HMAC.hexdigest("SHA256", "test-secret", [SOCKET_ID, channel, data].compact.join(":"))
  end

  test "signs a Turbo stream channel for its signed stream name" do
    channel = Hibira::Turbo.channel_name("room:1")
    post "/hibira/turbo/auth", params: {
      socket_id: SOCKET_ID, channel_name: channel,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name(["room", 1])
    }

    assert_response :ok
    assert_equal "test-key:#{signature(channel)}", response.parsed_body["auth"]
  end

  test "refuses a Turbo channel that does not match the signed stream name" do
    post "/hibira/turbo/auth", params: {
      socket_id: SOCKET_ID, channel_name: Hibira::Turbo.channel_name("room:2"),
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name(["room", 1])
    }
    assert_response :forbidden

    post "/hibira/turbo/auth", params: {
      socket_id: SOCKET_ID, channel_name: Hibira::Turbo.channel_name("room:1"), signed_stream_name: "forged"
    }
    assert_response :forbidden
  end

  test "refuses a bad socket ID" do
    post "/hibira/turbo/auth", params: {
      socket_id: "nope", channel_name: Hibira::Turbo.channel_name("room:1"),
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name(["room", 1])
    }
    assert_response :unprocessable_entity
  end

  test "authorizes private channels with authorize_channel" do
    Hibira.config.authorize_channel = lambda do |channel, controller|
      channel == "private-user.#{controller.current_user&.id}"
    end

    post "/hibira/auth", params: { socket_id: SOCKET_ID, channel_name: "private-user.7" }, headers: { "X-Test-User" => "7" }
    assert_response :ok
    assert_equal "test-key:#{signature('private-user.7')}", response.parsed_body["auth"]

    post "/hibira/auth", params: { socket_id: SOCKET_ID, channel_name: "private-user.8" }, headers: { "X-Test-User" => "7" }
    assert_response :forbidden
  end

  test "authorizes presence channels with member data" do
    Hibira.config.authorize_channel = lambda do |_channel, controller|
      user = controller.current_user
      user && { user_id: user.id, user_info: { name: user.name } }
    end

    post "/hibira/auth", params: { socket_id: SOCKET_ID, channel_name: "presence-room.1" }, headers: { "X-Test-User" => "3" }
    assert_response :ok
    data = response.parsed_body["channel_data"]
    assert_equal({ "user_id" => "3", "user_info" => { "name" => "User 3" } }, JSON.parse(data))
    assert_equal "test-key:#{signature('presence-room.1', data)}", response.parsed_body["auth"]

    post "/hibira/auth", params: { socket_id: SOCKET_ID, channel_name: "presence-room.1" }
    assert_response :forbidden
  end

  test "channel auth refuses without authorize_channel, for Turbo channels and public channels" do
    post "/hibira/auth", params: { socket_id: SOCKET_ID, channel_name: "private-user.1" }
    assert_response :forbidden

    Hibira.config.authorize_channel = ->(*) { true }
    post "/hibira/auth", params: { socket_id: SOCKET_ID, channel_name: Hibira::Turbo.channel_name("room:1") }
    assert_response :forbidden
    post "/hibira/auth", params: { socket_id: SOCKET_ID, channel_name: "news" }
    assert_response :forbidden
  end

  test "verifies webhooks and runs handlers" do
    received = []
    Hibira.on_webhook("channel_occupied") { |event| received << event["channel"] }
    Hibira.on_webhook { |event| received << "any:#{event['name']}" }
    body = { time_ms: 1, events: [{ name: "channel_occupied", channel: "news" }, { name: "member_added" }] }.to_json

    post "/hibira/webhooks", params: body, headers: webhook_headers(body)

    assert_response :ok
    assert_equal ["news", "any:channel_occupied", "any:member_added"], received
  end

  test "accepts the previous secret's signature during rotation" do
    body = { events: [] }.to_json
    headers = {
      "Content-Type" => "application/json", "X-Pusher-Key" => "test-key",
      "X-Pusher-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "new-secret", body),
      "X-Hibira-Previous-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "test-secret", body)
    }

    post "/hibira/webhooks", params: body, headers: headers
    assert_response :ok
  end

  test "refuses webhooks with a bad signature or key" do
    body = { events: [] }.to_json

    post "/hibira/webhooks", params: body, headers: webhook_headers(body).merge("X-Pusher-Signature" => "0" * 64)
    assert_response :unauthorized

    post "/hibira/webhooks", params: body, headers: webhook_headers(body).merge("X-Pusher-Key" => "other")
    assert_response :unauthorized
  end

  test "serves push tokens to the signed-in user only" do
    Hibira.config.push_instance_id = "instance"
    Hibira.config.push_secret_key = "s" * 64

    get "/hibira/push/token", params: { user_id: "5" }, headers: { "X-Test-User" => "5" }
    assert_response :ok
    token = response.parsed_body["token"]
    payload = JSON.parse(Base64.urlsafe_decode64(token.split(".")[1]))
    assert_equal "5", payload["sub"]

    get "/hibira/push/token", params: { user_id: "6" }, headers: { "X-Test-User" => "5" }
    assert_response :unauthorized

    get "/hibira/push/token", params: { user_id: "5" }
    assert_response :unauthorized
  end

  private

  def webhook_headers(body)
    {
      "Content-Type" => "application/json", "X-Pusher-Key" => "test-key",
      "X-Pusher-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "test-secret", body)
    }
  end
end
