// Turbo Streams over Hibira.
//
// Defines <hibira-turbo-stream-source>, which turbo_stream_from renders when
// the hibira-rails gem is set up. Each element subscribes to its stream's
// private channel and hands every "turbo-stream" event to Turbo, the way
// <turbo-cable-stream-source> does for Action Cable.
//
//   import "@hotwired/turbo-rails"
//   import "hibira/turbo"

import { Turbo } from "@hotwired/turbo-rails"
import Pusher from "pusher-js"

const EVENT = "turbo-stream"
const UNSUBSCRIBE_DELAY = 1000 // keeps the channel across a Turbo visit to a page with the same stream

let client = null
const streams = new Map() // channel name → { channel, elements, signedStreamName, authEndpoint, timer }

const META = { Key: "hibira-key", Host: "hibira-host", Port: "hibira-port", Tls: "hibira-tls", AuthEndpoint: "hibira-auth-endpoint" }

// A connection setting from the element's data-hibira-* attributes, falling
// back to the hibira_meta_tags meta tags.
function setting(element, name) {
  const value = element?.dataset?.[`hibira${name}`]
  if (value != null && value !== "") return value
  return document.querySelector(`meta[name="${META[name]}"]`)?.content
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

async function authorize({ socketId, channelName }, callback) {
  const stream = streams.get(channelName)
  const endpoint = stream ? stream.authEndpoint : setting(null, "AuthEndpoint") || "/hibira/auth"
  const body = new URLSearchParams({ socket_id: socketId, channel_name: channelName })
  if (stream) body.set("signed_stream_name", stream.signedStreamName)

  const headers = { Accept: "application/json" }
  const token = csrfToken()
  if (token) headers["X-CSRF-Token"] = token

  try {
    const response = await fetch(endpoint, { method: "POST", headers, body, credentials: "same-origin" })
    if (!response.ok) throw new Error(`Hibira auth for ${channelName} failed with ${response.status}`)
    callback(null, await response.json())
  } catch (error) {
    callback(error, null)
  }
}

// The shared pusher-js client, created from the first stream source element
// or, without one, from the hibira_meta_tags meta tags. Use it for your own
// channels too: hibira().subscribe("presence-room.1").
export function hibira(element = null) {
  if (client) return client

  const key = setting(element, "Key")
  if (!key) throw new Error("Hibira: no app key. Set HIBIRA_APP_KEY, or add <%= hibira_meta_tags %> to your layout.")

  const tls = setting(element, "Tls") !== "false"
  const port = Number(setting(element, "Port") || (tls ? 443 : 80))
  client = new Pusher(key, {
    cluster: "hkg", // required by pusher-js, unused once wsHost is set
    wsHost: setting(element, "Host") || "ws.hibira.io",
    wsPort: port,
    wssPort: port,
    forceTLS: tls,
    enabledTransports: ["ws", "wss"],
    channelAuthorization: { customHandler: authorize },
  })
  return client
}

class HibiraTurboStreamSourceElement extends HTMLElement {
  static observedAttributes = ["channel-name", "signed-stream-name"]

  connectedCallback() {
    Turbo.connectStreamSource(this)
    this.subscribe()
  }

  disconnectedCallback() {
    Turbo.disconnectStreamSource(this)
    this.unsubscribe()
  }

  attributeChangedCallback() {
    if (this.subscribedTo) {
      this.unsubscribe()
      this.subscribe()
    }
  }

  subscribe() {
    const name = this.getAttribute("channel-name")
    if (!name) return

    let stream = streams.get(name)
    if (!stream) {
      stream = { elements: new Set(), timer: null }
      streams.set(name, stream)
    }
    stream.signedStreamName = this.getAttribute("signed-stream-name")
    stream.authEndpoint = setting(this, "AuthEndpoint")
    clearTimeout(stream.timer)
    stream.channel ||= hibira(this).subscribe(name)

    this.receive = (data) => this.dispatchEvent(new MessageEvent("message", { data }))
    this.connected = () => this.setAttribute("connected", "")
    stream.channel.bind(EVENT, this.receive)
    stream.channel.bind("pusher:subscription_succeeded", this.connected)
    if (stream.channel.subscribed) this.connected()

    stream.elements.add(this)
    this.subscribedTo = name
  }

  unsubscribe() {
    const name = this.subscribedTo
    const stream = name && streams.get(name)
    this.subscribedTo = null
    this.removeAttribute("connected")
    if (!stream) return

    stream.channel.unbind(EVENT, this.receive)
    stream.channel.unbind("pusher:subscription_succeeded", this.connected)
    stream.elements.delete(this)

    if (stream.elements.size === 0) {
      clearTimeout(stream.timer)
      stream.timer = setTimeout(() => {
        if (stream.elements.size > 0) return
        client?.unsubscribe(name)
        streams.delete(name)
      }, UNSUBSCRIBE_DELAY)
    }
  }
}

if (customElements.get("hibira-turbo-stream-source") === undefined) {
  customElements.define("hibira-turbo-stream-source", HibiraTurboStreamSourceElement)
}
