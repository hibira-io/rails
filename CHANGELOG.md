# Changelog

## 0.4.0

- Fix: API requests are signed over the decoded path, as the server checks them, so IDs with a space or `/` no longer answer 401.
- Chat API: `Hibira::Chat` (`put_conversation`, `get_conversation`, `delete_conversation`, `add_members`, `remove_member`, `send_message`, `list_messages`, `mark_read`, `system_message`, `user_conversations`, and `request` for any other route).

## 0.3.0

- Approvals: `Hibira.request_approval(title:, ...)`, `Hibira.approval(id, wait:)` and `Hibira.wait_for_approval(id)` and `Hibira.reply_to_approval(id, message:)` ask a person for a decision and read the answer.
- Live Chat: `<%= hibira_live_chat %>` puts the Hibira Live Chat widget on the page; with `HIBIRA_LIVECHAT_IDENTITY_SECRET` the signed-in user is a verified visitor (`data-user-hash`). `Hibira::LiveChat.identity` and `.user_hash` for SPAs.

## 0.2.0

- Waiting rooms: `waiting_room "presale", only: :show` in controllers and
  `Hibira::WaitingRoom::Middleware` for path prefixes send visitors without a
  pass to the Hibira queue and let them in with a signed pass kept in an
  HttpOnly cookie (`hibira_pass` in the controller).
  `Hibira::WaitingRoom.verify_pass` checks a pass anywhere.

## 0.1.1

- README: cover image and screenshots.

## 0.1.0

- Turbo Streams over Hibira: every Turbo broadcast (`broadcasts_to`,
  `broadcast_*_to`, `broadcasts_refreshes`, the `_later` jobs) goes to a
  private Hibira channel, and `turbo_stream_from` subscribes through Hibira.
  No Action Cable server or Redis needed.
- Broadcasts over the app's event size limit are sent as a Turbo page refresh
  (`config.oversize`).
- Channel auth for your own private and presence channels
  (`config.authorize_channel`, `POST /hibira/auth`).
- Verified webhooks, including the previous secret during rotation
  (`Hibira.on_webhook`, `POST /hibira/webhooks`).
- `Hibira.push` and push user tokens (`GET /hibira/push/token`).
- `bin/rails generate hibira:install` and `bin/rails hibira:check`.
- Rails 7.0 to 8.1.
