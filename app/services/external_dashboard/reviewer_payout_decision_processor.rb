module ExternalDashboard
  class ReviewerPayoutDecisionProcessor
    DECISIONS = %w[approved rejected].freeze
    TEST_CONNECTION_DECISION = "test".freeze
    FALLBACK_ACTOR = "external_dashboard".freeze

    Result = Struct.new(:status, :body, keyword_init: true)

    def self.call(request_id, payload)
      new(request_id, payload).call
    end

    def initialize(request_id, payload)
      @request_id = request_id
      @payload = (payload || {}).with_indifferent_access
    end

    def call
      return ok_test if decision == TEST_CONNECTION_DECISION
      return error(:bad_request, "unsupported decision: #{decision.inspect}") unless DECISIONS.include?(decision)
      return error(:bad_request, "invalid adjustedAmount: #{payload[:adjustedAmount].inspect}") if invalid_adjusted_amount?

      payout_request = ::ReviewerPayoutRequest.find_by(id: request_id)
      return error(:not_found, "payout request not found (id=#{request_id.inspect})") if payout_request.nil?

      PaperTrail.request(whodunnit: whodunnit) { apply(payout_request) }
    end

    private

    attr_reader :request_id, :payload

    def decision
      payload[:decision].to_s
    end

    def apply(payout_request)
      success =
        if decision == "approved"
          payout_request.pay_out(admin: processor, adjusted_amount: adjusted_amount, adjust_reason: reason)
        else
          payout_request.reject_with_reason(admin: processor, reason: reason)
        end

      success ? ok(payout_request) : error(:unprocessable_entity, payout_request.errors.full_messages.to_sentence)
    end

    def raw_adjusted_amount
      payload[:adjustedAmount].to_s.presence
    end

    def invalid_adjusted_amount?
      raw_adjusted_amount.present? && adjusted_amount.nil?
    end

    def adjusted_amount
      return @adjusted_amount if defined?(@adjusted_amount)
      raw = raw_adjusted_amount
      @adjusted_amount = raw && raw.match?(Client::STRICT_INTEGER_PATTERN) ? Integer(raw, 10, exception: false) : nil
    end

    def reason
      payload[:reason].to_s.presence
    end

    def processor
      return @processor if defined?(@processor)
      slack_id = payload[:processedBy].to_s.presence
      @processor = slack_id && User.find_by(slack_id: slack_id)
    end

    def whodunnit
      processor&.id&.to_s || FALLBACK_ACTOR
    end

    def ok(payout_request)
      Result.new(status: :ok, body: {
        id: payout_request.id,
        status: payout_request.aasm_state,
        amount: payout_request.amount,
        adjustedAmount: payout_request.adjusted_amount,
        paidAmount: payout_request.paid_amount
      })
    end

    def ok_test
      Result.new(status: :ok, body: { status: "ok", test: true })
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::ReviewerPayoutDecisionProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end
  end
end
