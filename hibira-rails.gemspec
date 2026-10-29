# frozen_string_literal: true

require_relative "lib/hibira/version"

Gem::Specification.new do |spec|
  spec.name = "hibira-rails"
  spec.version = Hibira::VERSION
  spec.authors = ["Hibira"]
  spec.email = ["github@hibira.io"]

  spec.summary = "Turbo Streams, channel auth, webhooks and push notifications over Hibira for Rails"
  spec.description = "Sends Hotwire Turbo Stream broadcasts through Hibira, a hosted realtime service " \
                     "that speaks the Pusher Channels protocol, with no Action Cable server or Redis to run. " \
                     "Also signs private and presence channels, verifies webhooks and serves push tokens."
  spec.homepage = "https://hibira.io"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/hibira-io/rails",
    "changelog_uri" => "https://github.com/hibira-io/rails/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/hibira-io/rails/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["{app,config,lib}/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actioncable", ">= 7.0", "< 9"
  spec.add_dependency "pusher", ">= 2.0", "< 3"
  spec.add_dependency "railties", ">= 7.0", "< 9"
  spec.add_dependency "turbo-rails", ">= 1.5", "< 3"
end
