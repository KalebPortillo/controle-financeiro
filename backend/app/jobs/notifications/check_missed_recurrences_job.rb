module Notifications
  # Agendado diariamente via Solid Queue recurring (config/recurring.yml).
  class CheckMissedRecurrencesJob < ApplicationJob
    queue_as :default

    def perform
      CheckMissedRecurrences.call
    end
  end
end
