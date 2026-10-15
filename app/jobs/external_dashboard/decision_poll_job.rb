module ExternalDashboard
  class DecisionPollJob < ApplicationJob
    queue_as :literally_whenever

    def perform
      DecisionPollService.call
    end
  end
end
