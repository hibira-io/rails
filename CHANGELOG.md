# Changelog

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
