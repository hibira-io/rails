# frozen_string_literal: true

require "test_helper"

class ChatTest < ActiveSupport::TestCase
  include HibiraTestHelpers

  CHAT = %r{\Ahttps://ws\.hibira\.io/apps/1/chat/}

  def signature_ok?(request)
    params = URI.decode_www_form(request.uri.query).to_h
    sig = params.delete("auth_signature")
    sorted = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
    expected = OpenSSL::HMAC.hexdigest("SHA256", "test-secret", "#{request.method.to_s.upcase}\n#{request.uri.path}\n#{sorted}")
    md5_ok = request.body.to_s.empty? || params["body_md5"] == Digest::MD5.hexdigest(request.body)
    sig == expected && md5_ok
  end

  test "every call is signed with the right method and path" do
    seen = []
    stub_request(:any, CHAT).to_return do |request|
      seen << request
      { status: 200, body: '{"ok":true}' }
    end

    Hibira::Chat.put_conversation("order 42", name: "Order #42", members: %w[ann support])
    Hibira::Chat.get_conversation("c1")
    Hibira::Chat.add_members("c1", ["u2"])
    Hibira::Chat.remove_member("c1", "u/2")
    Hibira::Chat.send_message("c1", "ann", "Hi", push: "always")
    Hibira::Chat.list_messages("c1", after: 10, limit: 50)
    Hibira::Chat.mark_read("c1", "ann", 12)
    Hibira::Chat.system_message("c1", "Ann joined")
    Hibira::Chat.user_conversations("ann", limit: 20)
    Hibira::Chat.delete_conversation("c1")
    Hibira::Chat.request("POST", "conversations/c1/typing", body: { user_id: "ann" })

    assert_equal [
      "PUT /apps/1/chat/conversations/order%2042",
      "GET /apps/1/chat/conversations/c1",
      "POST /apps/1/chat/conversations/c1/members",
      "DELETE /apps/1/chat/conversations/c1/members/u%2F2",
      "POST /apps/1/chat/conversations/c1/messages",
      "GET /apps/1/chat/conversations/c1/messages",
      "POST /apps/1/chat/conversations/c1/read",
      "POST /apps/1/chat/conversations/c1/system",
      "GET /apps/1/chat/users/ann/conversations",
      "DELETE /apps/1/chat/conversations/c1",
      "POST /apps/1/chat/conversations/c1/typing"
    ], seen.map { |r| "#{r.method.to_s.upcase} #{r.uri.path}" }
    assert(seen.all? { |r| signature_ok?(r) })
    assert_equal({ "user_id" => "ann", "text" => "Hi", "push" => "always" }, JSON.parse(seen[4].body))
    assert_equal({ "after" => "10", "limit" => "50" }, URI.decode_www_form(seen[5].uri.query).to_h.slice("after", "limit"))
    assert_equal({ "user_id" => "ann", "seq" => 12 }, JSON.parse(seen[6].body))
    assert_nil seen[1].body
  end

  test "an empty 204 answer is an empty hash" do
    stub_request(:delete, CHAT).to_return(status: 204, body: "")
    assert_equal({}, Hibira::Chat.delete_conversation("c1"))
  end

  test "errors carry the status and the API's message" do
    stub_request(:get, CHAT).to_return(status: 402, body: '{"error":"Chat API is not on this plan"}')
    err = assert_raises(Hibira::Chat::Error) { Hibira::Chat.get_conversation("c1") }
    assert_equal 402, err.status
    assert_includes err.message, "Chat API is not on this plan"
    assert_raises(ArgumentError) { Hibira::Chat.get_conversation("") }
  end
end
