# frozen_string_literal: true

require "test_helper"

class HelperTest < ActionView::TestCase
  include HibiraTestHelpers
  include Turbo::StreamsHelper
  include Hibira::StreamsHelper

  test "turbo_stream_from renders a Hibira stream source" do
    html = turbo_stream_from("room", 1)
    element = Nokogiri::HTML5.fragment(html).at("hibira-turbo-stream-source")

    assert element
    assert_equal Hibira::Turbo.channel_name("room:1"), element["channel-name"]
    assert_equal "room:1", Turbo::StreamsChannel.verified_stream_name(element["signed-stream-name"])
    assert_equal "test-key", element["data-hibira-key"]
    assert_equal "ws.hibira.io", element["data-hibira-host"]
    assert_equal "443", element["data-hibira-port"]
    assert_equal "/hibira/turbo/auth", element["data-hibira-auth-endpoint"]
    refute_includes html, "test-secret"
  end

  test "turbo_stream_from keeps Action Cable for a custom channel or when off" do
    assert_includes turbo_stream_from("room", channel: "RoomChannel"), "<turbo-cable-stream-source"

    Hibira.config.turbo = false
    assert_includes turbo_stream_from("room"), "<turbo-cable-stream-source"
    assert_includes hibira_turbo_stream_from("room"), "<hibira-turbo-stream-source"
  end

  test "hibira_meta_tags lists the public settings" do
    html = hibira_meta_tags

    assert_includes html, '<meta name="hibira-key" content="test-key">'
    assert_includes html, '<meta name="hibira-auth-endpoint" content="/hibira/auth">'
    refute_includes html, "test-secret"
  end
end
