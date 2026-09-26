module ExternalDashboard
  class ReviewerPayoutSummary
    def initialize(user, requests, available_balance:)
      @user = user
      @requests = requests
      @available_balance = available_balance
    end

    def as_json(*)
      pending = requests.find(&:pending?)

      {
        user: { slackId: user.slack_id, displayName: user.display_name },
        availableBalance: available_balance,
        pendingRequest: pending && pending_json(pending),
        requests: requests.map { |request| request_json(request) }
      }
    end

    private

    attr_reader :user, :requests, :available_balance

    def pending_json(request)
      { id: request.id, amount: request.amount, createdAt: request.created_at.iso8601 }
    end

    def request_json(request)
      {
        id: request.id,
        status: request.aasm_state,
        amount: request.amount,
        adjustedAmount: request.adjusted_amount,
        paidAmount: request.paid_amount,
        adjustment: adjustment_delta(request),
        reason: request.adjust_reason,
        processedBy: processed_by_json(request),
        createdAt: request.created_at.iso8601,
        decidedAt: request.decided_at&.iso8601
      }
    end

    def adjustment_delta(request)
      return nil if request.adjusted_amount.nil?
      request.adjusted_amount - request.amount
    end

    def processed_by_json(request)
      return nil unless request.admin
      { slackId: request.admin.slack_id, displayName: request.admin.display_name }
    end
  end
end
