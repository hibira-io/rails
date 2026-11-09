# frozen_string_literal: true

require "test_helper"

class DropsController < ActionController::Base
  protect_from_forgery with: :exception
  waiting_room "presale", only: :show

  def show = render(plain: "in ##{hibira_pass.number}")
  def index = render(plain: "open")
end

class WaitingRoomTest < ActionDispatch::IntegrationTest
  include HibiraTestHelpers

  # Signed by the Hibira server (internal/waitroom NewPass) at 1800000000, ttl 30 min.
  SERVER_SECRET = "wr-secret-0123456789"
  SERVER_PASS = "eyJ2IjoxLCJhcHAiOiJ3ci1hcHAiLCJyb29tIjoicHJlc2FsZSIsIm4iOjQyLCJ0aWQiOiJkNzlmZTc4OWEzOGI4NjMxYjUiLCJpYXQiOjE4MDAwMDAw" \
                "MDAsImV4cCI6MTgwMDAwMTgwMH0.q7Uc_O6XKwNA_LVLQITlgv_YtDi9dIwiRzUUUSsGa08"
  SERVER_TICKET = "eyJ2IjoxLCJhcHAiOiJ3ci1hcHAiLCJyb29tIjoicHJlc2FsZSIsIm4iOjQyLCJ0aWQiOiJkNzlmZTc4OWEzOGI4NjMxYjUiLCJpYXQiOjE4MDAwMDAw" \
                  "MDAsImV4cCI6MTgwMDA4NjQwMH0.l-KNMOVwV_xJJCQaQ-JXQKsrj-XlEdsTxG7X4Kp_2ck"
  NOW = 1_800_000_100

  def setup
    super
    Rails.application.routes.draw do
      get "drops" => "drops#index"
      get "drops/:id" => "drops#show"
      post "drops/:id" => "drops#show"
    end
  end

  def teardown
    Rails.application.reload_routes!
    super
  end

  def sign(claims, secret = "test-secret")
    payload = Base64.urlsafe_encode64(JSON.generate(claims), padding: false)
    sig = OpenSSL::HMAC.digest("SHA256", secret, "hibira-waitroom-pass.#{payload}")
    "#{payload}.#{Base64.urlsafe_encode64(sig, padding: false)}"
  end

  def fresh(room = "presale")
    now = Time.now.to_i
    sign({ v: 1, app: "1", room: room, n: 7, tid: "t7", iat: now, exp: now + 600 })
  end

  def verify(token, **options) = Hibira::WaitingRoom.verify_pass(token, secret: SERVER_SECRET, now: NOW, **options)

  test "verifies a pass signed by the server" do
    pass = verify(SERVER_PASS, room: "presale", app_id: "wr-app")
    assert_equal [42, "d79fe789a38b8631b5", 1_800_001_800], [pass.number, pass.ticket_id, pass.expires_at]
    assert Hibira::WaitingRoom.verify_pass(SERVER_PASS, secret: ["old", SERVER_SECRET], now: NOW)
  end

  test "rejects forged, expired, foreign and ticket tokens" do
    assert_nil Hibira::WaitingRoom.verify_pass(SERVER_PASS, secret: "wrong", now: NOW)
    assert_nil verify(SERVER_PASS, room: "other")
    assert_nil verify(SERVER_PASS, app_id: "other")
    assert_nil Hibira::WaitingRoom.verify_pass(SERVER_PASS, secret: SERVER_SECRET, now: 1_800_001_800)
    assert_nil verify(SERVER_TICKET)
    assert_nil verify("#{SERVER_PASS[0...-3]}AAA")
    ["", nil, "a.b.c", "!!.??"].each { |bad| assert_nil verify(bad) }
  end

  test "builds the hosted page URL from the configured host" do
    assert_equal "https://ws.hibira.io/wait/test-key/presale?return=https%3A%2F%2Fshop.example.com%2Fdrops%3Fid%3D1",
                 Hibira::WaitingRoom.url("presale", "https://shop.example.com/drops?id=1")
  end

  test "sends visitors without a pass to the queue" do
    https!
    host! "shop.example.com"
    get "/drops/1?a=b"
    assert_response :found
    assert_equal Hibira::WaitingRoom.url("presale", "https://shop.example.com/drops/1?a=b"), response.location
    assert_equal "no-store", response.headers["cache-control"]

    get "/drops"
    assert_equal "open", response.body

    post "/drops/1"
    assert_response :forbidden
    assert_equal "waiting_room", JSON.parse(response.body)["error"]
    assert_equal "application/json", response.media_type
  end

  test "turns ?hibira_pass into a cookie, then lets the visitor in" do
    https!
    host! "shop.example.com"
    get "/drops/1?a=b&hibira_pass=#{fresh}"
    assert_response :found
    assert_equal "https://shop.example.com/drops/1?a=b", response.location
    assert_match(/hibira_wr_presale=.+; path=\/; max-age=\d+; secure; httponly; samesite=lax/i, response.headers["set-cookie"].to_s)

    get "/drops/1"
    assert_equal "in #7", response.body
  end

  test "a bad or foreign pass goes back to the queue" do
    [sign({ v: 1, app: "1", room: "presale", exp: 9e9 }, "nope"), fresh("other")].each do |token|
      get "/drops/1?hibira_pass=#{token}"
      assert_match %r{\Ahttps://ws\.hibira\.io/wait/test-key/presale\?return=http%3A%2F%2Fwww\.example\.com%2Fdrops%2F1\z}, response.location
    end
  end

  test "rack middleware protects prefixes" do
    app = Hibira::WaitingRoom::Middleware.new(->(env) { [200, {}, ["ok #{env['hibira.pass']&.number}"]] },
                                              "/drop" => "presale", "/drop/vip" => "vip")
    call = ->(path, cookie = nil) { app.call(Rack::MockRequest.env_for("http://shop.example.com#{path}", "HTTP_COOKIE" => cookie)) }
    assert_equal ["ok "], call.("/dropship")[2]
    assert_match "/wait/test-key/presale?", call.("/drop/a")[1]["location"]
    assert_match "/wait/test-key/vip?", call.("/drop/vip/a")[1]["location"]
    assert_equal ["ok 7"], call.("/drop/a", "hibira_wr_presale=#{fresh}")[2]
  end
end
