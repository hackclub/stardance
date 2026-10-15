module ExternalDashboard
  class ReviewerPayoutCreationProcessor
    TEST_CONNECTION_SLACK_ID = "test".freeze

    Result = Struct.new(:status, :body, keyword_init: true)

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = (payload || {}).with_indifferent_access
    end

    def call
      return ok_test if slack_id == TEST_CONNECTION_SLACK_ID
      return error(:bad_request, "missing slackId") if slack_id.nil?
      return error(:bad_request, "invalid amount: #{payload[:amount].inspect}") if amount.nil?

      user = User.find_by(slack_id: slack_id)
      return error(:not_found, "no Stardance user for slackId=#{slack_id.inspect}") if user.nil?

      request = ::ReviewerPayoutRequest.new(user: user, amount: amount)

      if request.save
        ok(request)
      else
        error(:unprocessable_entity, request.errors.full_messages.to_sentence)
      end
    rescue ActiveRecord::RecordNotUnique
      error(:unprocessable_entity, "user already has a pending payout request")
    end

    private

    attr_reader :payload

    def slack_id
      payload[:slackId].to_s.presence
    end

    def amount
      raw = payload[:amount].to_s
      raw.match?(Client::STRICT_INTEGER_PATTERN) ? Integer(raw, 10, exception: false) : nil
    end

    def ok(request)
      Result.new(status: :created, body: { id: request.id, amount: request.amount, status: request.aasm_state })
    end

    def ok_test
      Result.new(status: :ok, body: { status: "ok", test: true })
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::ReviewerPayoutCreationProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end
  end
end
