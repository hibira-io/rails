# frozen_string_literal: true

require "hibira/approvals"

module Hibira
  # The Chat API (https://hibira.io/chat-api): conversations with stored
  # history, read receipts and offline push. Users receive chat.* events on
  # #server-to-user-<id> after pusher.signin().
  #
  #   Hibira::Chat.put_conversation("order-42", name: "Order #42", members: %w[ann support])
  #   Hibira::Chat.send_message("order-42", "ann", "Where is my parcel?")
  #   Hibira::Chat.list_messages("order-42", after: 0, limit: 50)
  module Chat
    # Raised when the API answers with an error (status and the API's message).
    class Error < Approvals::Error; end

    module_function

    # Any Chat API call, signed. path is relative to /apps/APP_ID/chat, such
    # as "/conversations/c1/typing".
    def request(method, path, query: {}, body: nil)
      path = "/#{path}" unless path.start_with?("/")
      body = {} if body.nil? && %w[POST PUT].include?(method)
      Approvals.call(method, "/chat#{path}", query: query.compact.transform_values(&:to_s), body: body, error: Error)
    end

    # Creates or replaces a conversation: name, members, metadata, roles, watchers.
    def put_conversation(conversation_id, **fields)
      request("PUT", "/conversations/#{seg(conversation_id)}", body: fields)
    end

    def get_conversation(conversation_id)
      request("GET", "/conversations/#{seg(conversation_id)}")
    end

    # Deletes a conversation with its members, messages and files.
    def delete_conversation(conversation_id)
      request("DELETE", "/conversations/#{seg(conversation_id)}")
    end

    def add_members(conversation_id, user_ids)
      request("POST", "/conversations/#{seg(conversation_id)}/members", body: { user_ids: Array(user_ids).map(&:to_s) })
    end

    def remove_member(conversation_id, user_id)
      request("DELETE", "/conversations/#{seg(conversation_id)}/members/#{seg(user_id)}")
    end

    # Posts a message as a member. fields may add name, metadata, push
    # ("offline", "always", "never"), push_title, push_url, visible_to and
    # idempotency_key.
    def send_message(conversation_id, user_id, text = nil, **fields)
      body = { user_id: user_id.to_s }
      body[:text] = text unless text.nil?
      request("POST", "/conversations/#{seg(conversation_id)}/messages", body: body.merge(fields))
    end

    # Messages oldest first after a seq (0 for the start).
    def list_messages(conversation_id, after: nil, limit: nil, last: nil)
      request("GET", "/conversations/#{seg(conversation_id)}/messages", query: { after: after, limit: limit, last: last })
    end

    def mark_read(conversation_id, user_id, seq)
      request("POST", "/conversations/#{seg(conversation_id)}/read", body: { user_id: user_id.to_s, seq: Integer(seq) })
    end

    # A system message (no sender), such as "Alice joined".
    def system_message(conversation_id, text, **fields)
      request("POST", "/conversations/#{seg(conversation_id)}/system", body: { text: text }.merge(fields))
    end

    # A user's conversations, newest activity first.
    def user_conversations(user_id, limit: nil, before: nil)
      request("GET", "/users/#{seg(user_id)}/conversations", query: { limit: limit, before: before })
    end

    def seg(id)
      raise ArgumentError, "an ID is required" if id.to_s.empty?

      ERB::Util.url_encode(id.to_s)
    end
  end
end
