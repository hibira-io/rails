# frozen_string_literal: true

require "test_helper"

class TurboTest < ActiveSupport::TestCase
  include HibiraTestHelpers

  test "names one private channel per stream" do
    name = Hibira::Turbo.channel_name("gid://dummy/Room/1:messages")

    assert_match(/\Aprivate-turbo-[0-9a-f]{64}\z/, name)
    assert_equal name, Hibira::Turbo.channel_name("gid://dummy/Room/1:messages")
    refute_equal name, Hibira::Turbo.channel_name("gid://dummy/Room/2:messages")
  end

  test "sends Turbo broadcasts to Hibira" do
    events = stub_events

    Turbo::StreamsChannel.broadcast_append_to("room", 1, target: "messages", html: "<p>Hi</p>")

    assert_equal 1, events.length
    assert_equal "turbo-stream", events[0]["name"]
    assert_equal [Hibira::Turbo.channel_name("room:1")], events[0]["channels"]
    assert_includes events[0]["data"], 'action="append"'
    assert_includes events[0]["data"], "<p>Hi</p>"
  end

  test "sends refresh and _later broadcasts to Hibira" do
    skip "page refreshes need turbo-rails 2" unless Turbo::StreamsChannel.respond_to?(:broadcast_refresh_to)

    events = stub_events

    Turbo::StreamsChannel.broadcast_refresh_to("room")
    Turbo::StreamsChannel.broadcast_replace_later_to("room", target: "title", html: "New")

    assert_equal 2, events.length
    assert_includes events[0]["data"], 'action="refresh"'
    assert_includes events[1]["data"], 'action="replace"'
  end

  test "skips blank streamables like Turbo does" do
    events = stub_events

    Turbo::StreamsChannel.broadcast_remove_to(nil, target: "x")

    assert_empty events
  end

  test "sends a page refresh when a broadcast is too large" do
    events = stub_events(413, 200)

    Turbo::StreamsChannel.broadcast_append_to("room", target: "messages", html: "x" * 20_000)

    assert_equal 2, events.length
    assert_equal Hibira::Turbo::REFRESH, events[1]["data"]
  end

  test "drops or raises on a too large broadcast when asked" do
    events = stub_events(413)

    Hibira.config.oversize = :log
    assert_nil Turbo::StreamsChannel.broadcast_append_to("room", target: "messages", html: "x")
    assert_equal 1, events.length

    Hibira.config.oversize = :raise
    assert_raises(Hibira::PayloadTooLarge) do
      Turbo::StreamsChannel.broadcast_append_to("room", target: "messages", html: "x")
    end
  end

  test "uses Action Cable when Turbo over Hibira is off" do
    events = stub_events
    Hibira.config.turbo = false
    broadcasts = []
    server = ActionCable.server
    server.define_singleton_method(:broadcast) { |stream, content| broadcasts << [stream, content] }

    Turbo::StreamsChannel.broadcast_remove_to("room", target: "x")

    assert_empty events
    assert_equal "room", broadcasts.dig(0, 0)
  ensure
    server.singleton_class.remove_method(:broadcast)
  end

  test "auto mode stays on Action Cable in tests and without credentials" do
    Hibira.config.turbo = :auto
    refute Hibira.config.turbo?

    Hibira.config.turbo = true
    Hibira.config.key = ""
    refute Hibira.config.configured?
  end
end
