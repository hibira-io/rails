# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails = ENV.fetch("RAILS_VERSION", "8.1")
gem "rails", "~> #{rails}.0"
turbo = ENV.fetch("TURBO_RAILS_VERSION", "")
gem "turbo-rails", turbo.empty? ? ">= 1.5" : "~> #{turbo}"

gem "minitest", "~> 5.0"
gem "pusher-push-notifications", "~> 2.0"
gem "rake"
gem "webmock", "~> 3.0"
