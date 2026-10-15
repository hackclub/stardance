module ExternalDashboard
  class ReviewerPayoutStatusProcessor
    TEST_CONNECTION_SLACK_ID = "test".freeze

    Result = Struct.new(:status, :body, keyword_init: true)

    def self.call(slack_id:)
      new(slack_id).call
    end

    def initialize(slack_id)
      @slack_id = slack_id.to_s.presence
    end

    def call
      return ok_test if slack_id == TEST_CONNECTION_SLACK_ID
      return error(:bad_request, "missing slackId") if slack_id.nil?

      user = User.find_by(slack_id: slack_id)
      return error(:not_found, "no Stardance user for slackId=#{slack_id.inspect}") if user.nil?

      summary = ReviewerPayoutSummary.new(
        user,
        ::ReviewerPayoutRequest.history_for(user),
        available_balance: ::ReviewerPayoutRequest.available_to_request_for(user)
      )
      ok(summary.as_json)
    end

    private

    attr_reader :slack_id

    def ok(body)
      Result.new(status: :ok, body: body)
    end

    def ok_test
      Result.new(status: :ok, body: { status: "ok", test: true })
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::ReviewerPayoutStatusProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end
  end
end
