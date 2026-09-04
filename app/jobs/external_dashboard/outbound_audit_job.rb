module ExternalDashboard
  class OutboundAuditJob < ApplicationJob
    queue_as :literally_whenever

    def perform
      OutboundAuditService.call
    end
  end
end
