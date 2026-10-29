# frozen_string_literal: true

namespace :hibira do
  desc "Check the Hibira settings and credentials"
  task check: :environment do
    ok, lines = Hibira::Check.run
    puts lines
    exit 1 unless ok
  end
end
