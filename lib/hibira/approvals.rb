# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "digest/md5"
require "erb"
require "uri"

module Hibira
  class Error < StandardError; end

  # Hibira Approvals (https://hibira.io/approvals): ask a person for a
  # decision from your app, an agent or a job, and read the answer.
  #
  #   approval = Hibira.request_approval(title: "Refund order #1042 for $89?", channel: "private-ops")
  #   # share approval["url"], then
  #   approval = Hibira.wait_for_approval(approval["approval_id"])
  #   refund! if approval["status"] == "approved"
  module Approvals
    MAX_WAIT = 25
    FIELDS = %i[details options expires_in_minutes channel push_interests push_users agent].freeze

    # Raised when the API answers with an error (status and the API's message).
    class Error < Hibira::Error
      attr_reader :status, :body

      def initialize(status, message, body = nil)
        @status = status
        @body = body
        super("#{status}: #{message}")
      end
    end

    module_function

    # Creates an approval. options are 2 to 4 choices (the first approves);
    # expires_in_minutes is 1 to 10080 (default 60). Returns the approval
    # with its answer page in "url".
    def request(title:, **fields)
      raise ArgumentError, "title is required" if title.to_s.strip.empty?

      unknown = fields.keys - FIELDS
      raise ArgumentError, "unknown approval fields: #{unknown.join(', ')}" if unknown.any?

      body = { title: title.to_s }
      fields.each { |k, v| body[k] = v unless v.nil? }
      call("POST", "/approvals", body: body)
    end

    # An approval's status. wait (seconds, up to 25) holds the request until
    # it is answered.
    def get(approval_id, wait: 0)
      raise ArgumentError, "approval_id is required" if approval_id.to_s.empty?

      wait = wait.to_i.clamp(0, MAX_WAIT)
      query = wait.positive? ? { "wait" => wait.to_s } : {}
      call("GET", "/approvals/#{ERB::Util.url_encode(approval_id.to_s)}", query: query, read_timeout: wait + 10)
    end

    # Polls until the approval is no longer pending, or timeout seconds pass,
    # and returns it.
    def wait_for(approval_id, timeout: 3600)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        approval = get(approval_id, wait: [left, MAX_WAIT].min)
        return approval if approval["status"] != "pending" || left <= MAX_WAIT
      end
    end

    # The signed query string of a Channels-protocol HTTP API request.
    def signed_query(method, path, query, body, key:, secret:, timestamp: Time.now.to_i)
      params = query.transform_keys(&:to_s).merge(
        "auth_key" => key,
        "auth_timestamp" => timestamp.to_s,
        "auth_version" => "1.0"
      )
      params["body_md5"] = Digest::MD5.hexdigest(body) if body
      sorted = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{method}\n#{path}\n#{sorted}")
      URI.encode_www_form(params.sort.to_h.merge("auth_signature" => signature))
    end

    def call(method, resource, query: {}, body: nil, read_timeout: 15)
      config = Hibira.config
      unless config.configured?
        raise MissingCredentials, "Hibira is not configured: set #{config.missing.join(', ')}"
      end

      path = "/apps/#{config.app_id}#{resource}"
      json = body && JSON.generate(body)
      qs = signed_query(method, path, query, json, key: config.key, secret: config.secret)
      uri = (config.use_tls ? URI::HTTPS : URI::HTTP).build(host: config.host, port: config.port, path: path, query: qs)
      request = method == "POST" ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request["User-Agent"] = "hibira-rails/#{Hibira::VERSION}"
      if json
        request["Content-Type"] = "application/json"
        request.body = json
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     open_timeout: 10, read_timeout: read_timeout) do |http|
        http.request(request)
      end
      parse(response)
    end

    def parse(response)
      data = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end
      return data if response.is_a?(Net::HTTPSuccess) && data.is_a?(Hash)

      message = data.is_a?(Hash) && data["error"] ? data["error"].to_s : response.body.to_s.strip
      raise Error.new(response.code.to_i, message.empty? ? response.message.to_s : message, response.body)
    end
  end

  class << self
    # Hibira.request_approval(title: "Deploy v2 to production?", options: %w[Deploy Wait])
    def request_approval(title:, **fields)
      Approvals.request(title: title, **fields)
    end

    # Hibira.approval("apr_…", wait: 25)
    def approval(approval_id, wait: 0)
      Approvals.get(approval_id, wait: wait)
    end

    # Hibira.wait_for_approval("apr_…", timeout: 600)
    def wait_for_approval(approval_id, timeout: 3600)
      Approvals.wait_for(approval_id, timeout: timeout)
    end
  end
end
