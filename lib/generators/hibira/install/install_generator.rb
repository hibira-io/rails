# frozen_string_literal: true

require "rails/generators"

module Hibira
  module Generators
    # bin/rails generate hibira:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Sets up Hibira: an initializer, pusher-js and the hibira/turbo JavaScript module."

      class_option :skip_install, type: :boolean, default: false, desc: "Don't install pusher-js"

      def create_initializer
        template "hibira.rb", "config/initializers/hibira.rb"
      end

      def install_javascript
        if importmap?
          run "bin/importmap pin pusher-js" unless options[:skip_install]
          import_in_application_js 'import "hibira/turbo"'
        elsif File.exist?(File.join(destination_root, "package.json"))
          copy_file File.expand_path("../../../../app/javascript/hibira/turbo.js", __dir__), "app/javascript/hibira/turbo.js"
          run "#{package_manager} pusher-js" unless options[:skip_install]
          import_in_application_js 'import "./hibira/turbo"'
        else
          say "No importmap or package.json found. Load pusher-js and the hibira/turbo module " \
              "(#{File.expand_path('../../../../app/javascript/hibira/turbo.js', __dir__)}) yourself.", :yellow
        end
      end

      def show_next_steps
        say <<~TEXT

          Hibira is installed. Copy the app ID, key and secret from your app page on
          https://hibira.io/portal into the environment:

            HIBIRA_APP_ID=your-app-id
            HIBIRA_APP_KEY=your-app-key
            HIBIRA_APP_SECRET=your-app-secret

          or into bin/rails credentials:edit under hibira: (app_id, key, secret).
          Then check them with:

            bin/rails hibira:check
        TEXT
      end

      private

      def importmap?
        File.exist?(File.join(destination_root, "config/importmap.rb"))
      end

      def package_manager
        if File.exist?(File.join(destination_root, "bun.lockb")) || File.exist?(File.join(destination_root, "bun.lock"))
          "bun add"
        elsif File.exist?(File.join(destination_root, "yarn.lock"))
          "yarn add"
        elsif File.exist?(File.join(destination_root, "pnpm-lock.yaml"))
          "pnpm add"
        else
          "npm install"
        end
      end

      def import_in_application_js(line)
        path = "app/javascript/application.js"
        full = File.join(destination_root, path)
        unless File.exist?(full)
          say "Add #{line} to your JavaScript entry point after @hotwired/turbo-rails.", :yellow
          return
        end
        return if File.read(full).include?(line)

        if File.read(full).match?(%r{^import ["']@hotwired/turbo-rails["'].*$})
          inject_into_file path, "\n#{line}", after: %r{^import ["']@hotwired/turbo-rails["'].*$}
        else
          append_to_file path, "#{line}\n"
        end
      end
    end
  end
end
