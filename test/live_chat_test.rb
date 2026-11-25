# frozen_string_literal: true

require "test_helper"

class LiveChatTest < ActionView::TestCase
  include HibiraTestHelpers
  include Hibira::LiveChatHelper

  Person = Struct.new(:id, :first_name, :last_name, :email)

  def script(html)
    Nokogiri::HTML5.fragment(html).at("script")
  end

  def sign_in(user)
    controller.define_singleton_method(:current_user) { user }
  end

  test "user_hash is the HMAC-SHA256 of the user ID" do
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", "lcid_s", "42"), Hibira::LiveChat.user_hash("lcid_s", 42)
    assert_raises(ArgumentError) { Hibira::LiveChat.user_hash("", 1) }
  end

  test "renders nothing without a workspace" do
    assert_equal "", hibira_live_chat
  end

  test "renders the widget for anonymous visitors with options" do
    Hibira.config.livechat_workspace = "ws_1"
    el = script(hibira_live_chat(color: "#0a7", lang: "ja", launcher: false))

    assert_equal "https://chat.hibira.io/w/v1.js", el["src"]
    assert_equal "ws_1", el["data-workspace"]
    assert_equal "#0a7", el["data-color"]
    assert_equal "ja", el["data-lang"]
    assert_equal "none", el["data-launcher"]
    assert el.key?("async")
    assert_nil el["data-user-id"]
  end

  test "a signed-in user is verified only with an identity secret" do
    Hibira.config.livechat_workspace = "ws_1"
    sign_in(User.new(7, "Aiko <A>"))
    assert_nil script(hibira_live_chat)["data-user-id"]

    Hibira.config.livechat_identity_secret = "lcid_s"
    el = script(hibira_live_chat)

    assert_equal "7", el["data-user-id"]
    assert_equal Hibira::LiveChat.user_hash("lcid_s", 7), el["data-user-hash"]
    assert_equal "Aiko <A>", el["data-user-name"]
    refute_includes hibira_live_chat, "Aiko <A>"
  end

  test "identity uses first and last name and email" do
    Hibira.config.livechat_identity_secret = "lcid_s"
    who = Hibira::LiveChat.identity(Person.new(3, "Ann", "Lee", "ann@example.com"))

    assert_equal({ id: "3", hash: Hibira::LiveChat.user_hash("lcid_s", 3), name: "Ann Lee", email: "ann@example.com" }, who)
    assert_nil Hibira::LiveChat.identity(nil)
  end

  test "settings fall back to the environment" do
    ENV["HIBIRA_LIVECHAT_WORKSPACE"] = "ws_env"
    assert_equal "ws_env", script(hibira_live_chat)["data-workspace"]
  ensure
    ENV.delete("HIBIRA_LIVECHAT_WORKSPACE")
  end
end
