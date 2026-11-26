# frozen_string_literal: true

require "test_helper"

class ApprovalsTest < ActiveSupport::TestCase
  include HibiraTestHelpers

  APPROVALS = %r{\Ahttps://ws\.hibira\.io/apps/1/approvals}

  def approval(status = "pending")
    { "approval_id" => "apr_1", "title" => "Refund?", "options" => %w[Approve Reject],
      "status" => status, "url" => "https://approvals.hibira.io/a/apr_1" }
  end

  def signature_ok?(request)
    params = URI.decode_www_form(request.uri.query).to_h
    sig = params.delete("auth_signature")
    sorted = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
    path = URI.decode_www_form_component(request.uri.path.gsub("+", "%2B"))
    expected = OpenSSL::HMAC.hexdigest("SHA256", "test-secret", "#{request.method.to_s.upcase}\n#{path}\n#{sorted}")
    md5_ok = request.body.to_s.empty? || params["body_md5"] == Digest::MD5.hexdigest(request.body)
    sig == expected && md5_ok
  end

  test "request_approval posts a signed request and returns the created approval" do
    seen = nil
    stub_request(:post, APPROVALS).to_return do |request|
      seen = request
      { status: 201, body: approval.to_json, headers: { "Content-Type" => "application/json" } }
    end

    out = Hibira.request_approval(title: "Refund?", options: %w[Approve Reject], channel: "private-ops", agent: nil)

    assert_equal "apr_1", out["approval_id"]
    assert signature_ok?(seen)
    assert_equal({ "title" => "Refund?", "options" => %w[Approve Reject], "channel" => "private-ops" }, JSON.parse(seen.body))
    assert_equal "/apps/1/approvals", seen.uri.path
  end

  test "request_approval checks its arguments" do
    assert_raises(ArgumentError) { Hibira.request_approval(title: " ") }
    assert_raises(ArgumentError) { Hibira.request_approval(title: "x", colour: "red") }
  end

  test "approval passes wait capped at 25 seconds and escapes the ID" do
    seen = nil
    stub_request(:get, APPROVALS).to_return do |request|
      seen = request
      { status: 200, body: approval("approved").to_json }
    end

    assert_equal "approved", Hibira.approval("apr/1", wait: 90)["status"]
    assert_equal "/apps/1/approvals/apr%2F1", seen.uri.path
    assert_equal "25", URI.decode_www_form(seen.uri.query).to_h["wait"]
    assert signature_ok?(seen)
  end

  test "reply_to_approval posts the reply" do
    seen = nil
    stub_request(:post, APPROVALS).to_return do |request|
      seen = request
      { status: 201, body: approval.to_json }
    end

    Hibira.reply_to_approval("apr_1", message: "Staging only", details: "DELETE ... LIMIT 12")
    assert_equal "/apps/1/approvals/apr_1/replies", seen.uri.path
    assert_equal({ "message" => "Staging only", "details" => "DELETE ... LIMIT 12" }, JSON.parse(seen.body))
    assert signature_ok?(seen)
    assert_raises(ArgumentError) { Hibira.reply_to_approval("apr_1", message: "") }
  end

  test "wait_for_approval polls until answered" do
    stub_request(:get, APPROVALS)
      .to_return({ status: 200, body: approval.to_json }, { status: 200, body: approval("rejected").to_json })

    assert_equal "rejected", Hibira.wait_for_approval("apr_1", timeout: 600)["status"]
    assert_requested :get, APPROVALS, times: 2
  end

  test "errors carry the status and the API's message" do
    stub_request(:post, APPROVALS).to_return(status: 403, body: '{"error":"Approvals is not on this plan"}')

    err = assert_raises(Hibira::Approvals::Error) { Hibira.request_approval(title: "x") }
    assert_equal 403, err.status
    assert_includes err.message, "Approvals is not on this plan"
  end
end
