# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/hibira/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Hibira::Generators::InstallGenerator
  destination File.expand_path("../tmp/generator", __dir__)
  setup :prepare_destination

  test "writes the initializer and imports the module in an importmap app" do
    mkdir_p "config"
    File.write(File.join(destination_root, "config/importmap.rb"), %(pin "@hotwired/turbo-rails", to: "turbo.min.js"\n))
    mkdir_p "app/javascript"
    File.write(File.join(destination_root, "app/javascript/application.js"), %(import "@hotwired/turbo-rails"\nimport "controllers"\n))

    run_generator %w[--skip-install]

    assert_file "config/initializers/hibira.rb", /Hibira.configure/
    assert_file "app/javascript/application.js", %r{import "@hotwired/turbo-rails"\nimport "hibira/turbo"\nimport "controllers"}
  end

  test "copies the module in a bundler app" do
    File.write(File.join(destination_root, "package.json"), "{}")
    mkdir_p "app/javascript"
    File.write(File.join(destination_root, "app/javascript/application.js"), %(import "@hotwired/turbo-rails"\n))

    run_generator %w[--skip-install]

    assert_file "app/javascript/hibira/turbo.js", /hibira-turbo-stream-source/
    assert_file "app/javascript/application.js", %r{import "./hibira/turbo"}
  end

  private

  def mkdir_p(path)
    FileUtils.mkdir_p(File.join(destination_root, path))
  end
end
