# hibira-rails

[![ci](https://github.com/hibira-io/rails/actions/workflows/ci.yml/badge.svg)](https://github.com/hibira-io/rails/actions/workflows/ci.yml)

Hotwire Turbo Streams over [Hibira](https://hibira.io), with no Action Cable
server, Redis or Solid Cable to run.

Hibira is a hosted realtime service that speaks the Pusher Channels protocol.
This gem sends every Turbo Stream broadcast your app already makes through
Hibira, and makes `turbo_stream_from` subscribe through it. Your models and
views stay as they are. It also signs your own private and presence
channels, verifies webhooks and serves push notification tokens.

Supports Rails 7.0 to 8.1 (Ruby 3.1+) and turbo-rails 1.5 to 2.

## Install

```sh
bundle add hibira-rails
bin/rails generate hibira:install
```

The generator writes `config/initializers/hibira.rb`, pins `pusher-js` (or
installs it with your package manager in a jsbundling app) and imports the
`hibira/turbo` module after `@hotwired/turbo-rails` in
`app/javascript/application.js`.

Copy the app ID, key and secret from your app page on
[hibira.io/portal](https://hibira.io/portal) (the free plan needs no card)
into the environment:

```sh
HIBIRA_APP_ID=your-app-id
HIBIRA_APP_KEY=your-app-key
HIBIRA_APP_SECRET=your-app-secret
```

or into `bin/rails credentials:edit`:

```yaml
hibira:
  app_id: your-app-id
  key: your-app-key
  secret: your-app-secret
```

The secret is shown only once, when you create the app; the app ID and key
stay under Overview → Credentials. On the Free plan, allowed origins can't be
`*`: add every origin your pages load from (`http://localhost:3000` while
developing, plus your production domain), or browsers are refused.

Then check them:

```sh
bin/rails hibira:check
```

## Turbo Streams

Nothing changes in your code. This model and view, straight from the Turbo
handbook, now update every open page through Hibira:

```ruby
class Message < ApplicationRecord
  belongs_to :room
  broadcasts_to :room
end
```

```erb
<%= turbo_stream_from @room %>
<div id="messages"><%= render @room.messages %></div>
```

`broadcast_append_to`, `broadcast_replace_later_to`, `broadcasts_refreshes`
and the rest all go through Hibira, from requests and from Active Job alike.

Each Turbo stream maps to one private channel. `turbo_stream_from` renders a
`<hibira-turbo-stream-source>` element holding the signed stream name, and the
browser can only subscribe with it (checked at `POST /hibira/turbo/auth`), the
same rule Action Cable applies. The app secret never leaves the server.

Turbo goes through Hibira whenever the credentials are set, except in the
test environment, where Turbo's `assert_turbo_stream_broadcasts` keeps working
on Action Cable. Force it either way:

```ruby
Hibira.configure do |config|
  config.turbo = true # or false
end
```

A `turbo_stream_from` with a custom Action Cable channel
(`turbo_stream_from @room, channel: RoomChannel`) still uses Action Cable.

### Large broadcasts

Each plan has an event size limit (4 KB on Free). When a Turbo Stream is
larger, the gem sends a Turbo 8 page refresh instead, so open pages still
catch up. For pages with long lists, `broadcasts_refreshes` with
`turbo_refreshes_with method: :morph` keeps every broadcast tiny:

```ruby
class Room < ApplicationRecord
  broadcasts_refreshes
end
```

Set `config.oversize = :log` to drop large broadcasts instead, or `:raise`
to raise `Hibira::PayloadTooLarge`.

## Your own channels

`Hibira.trigger` is the pusher-http-ruby client, already pointed at Hibira:

```ruby
Hibira.trigger("orders", "order-shipped", { id: 1024 })
Hibira.client.channel_info("presence-room.1", info: "user_count")
```

To sign private and presence channels, set `authorize_channel`. It receives
the channel name and the controller, which inherits from your
`ApplicationController`, so `current_user` and CSRF protection work as usual:

```ruby
Hibira.configure do |config|
  config.authorize_channel = lambda do |channel, controller|
    user = controller.send(:current_user)
    case channel
    when /\Aprivate-user\.(\d+)\z/ then user&.id == $1.to_i
    when /\Apresence-room\.(\d+)\z/ then user && { user_id: user.id, user_info: { name: user.name } }
    end
  end
end
```

In the browser, reuse the client the Turbo module created:

```erb
<%# in your layout, for pages without turbo_stream_from %>
<%= hibira_meta_tags %>
```

```js
import { hibira } from "hibira/turbo"

hibira().subscribe("private-user.42").bind("order-shipped", (order) => console.log(order))
```

It authorizes at `POST /hibira/auth` with the page's CSRF token. For presence
rooms with thousands of members, use a `presence-large-*` channel and
[`@hibira-io/large-presence`](https://github.com/hibira-io/large-presence-js).

## Webhooks

Add `https://your-app.example.com/hibira/webhooks` on your app page →
Webhooks, then handle events in an initializer:

```ruby
Hibira.on_webhook("channel_vacated") do |event|
  Room.find_by(channel: event["channel"])&.close!
end

Hibira.on_webhook { |event| Rails.logger.info("Hibira: #{event['name']}") } # every event
```

The signature is checked against your app secret. While a rotated-out secret
is in its grace period, Hibira also signs with the old one
(`X-Hibira-Previous-Signature`), so webhooks keep arriving until you
redeploy. Each event is also instrumented as `webhook.hibira` with
`ActiveSupport::Notifications`.

## Push notifications

Enable push on your app page (Push notifications), upload your APNs key or
FCM service account there, add `gem "pusher-push-notifications"` and set:

```sh
HIBIRA_PUSH_INSTANCE_ID=your-instance-id
HIBIRA_PUSH_SECRET_KEY=your-secret-key
```

```ruby
Hibira.push.publish_to_users(
  users: [order.user_id.to_s],
  payload: {
    apns: { aps: { alert: { title: "Order shipped", body: "Order ##{order.id} is on its way." } } },
    fcm: { notification: { title: "Order shipped", body: "Order ##{order.id} is on its way." } },
    web: { notification: { title: "Order shipped", body: "Order ##{order.id} is on its way.", deep_link: order_url(order) } }
  }
)
```

`GET /hibira/push/token?user_id=…` returns a user token for `setUserId` in the
web, Android and iOS SDKs. It answers only for the signed-in user
(`current_user` or `Current.user`; change it with `config.push_user_id`).

## Settings

| Setting | Environment | Default |
| --- | --- | --- |
| `app_id`, `key`, `secret` | `HIBIRA_APP_ID`, `HIBIRA_APP_KEY`, `HIBIRA_APP_SECRET` | |
| `host` | `HIBIRA_HOST` | `ws.hibira.io` (or `ws-<cluster>.hibira.io`, as shown on your app page) |
| `port`, `use_tls` | `HIBIRA_PORT`, `HIBIRA_USE_TLS` | `443`, `true` |
| `turbo` | | `:auto` |
| `oversize` | | `:refresh` |
| `authorize_channel` | | refuses all |
| `push_instance_id`, `push_secret_key` | `HIBIRA_PUSH_INSTANCE_ID`, `HIBIRA_PUSH_SECRET_KEY` | |
| `push_endpoint` | `HIBIRA_PUSH_ENDPOINT` | `https://<host>` |
| `push_user_id` | | `current_user&.id` or `Current.user&.id` |
| `parent_controller` | | `"ApplicationController"` |
| `draw_routes`, `route_prefix` | | `true`, `"hibira"` |
| `client_options` | | `{}` (passed to `Pusher::Client.new`) |

Values set in `Hibira.configure` win over the environment, which wins over
credentials.

## License

MIT
