module ExternalDashboard
  class DecisionProcessor
    DECISION_EVENT = "certification.decision".freeze
    TEST_EVENT = "test".freeze

    Result = Struct.new(:status, :body, keyword_init: true)

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = (payload || {}).with_indifferent_access
    end

    def call
      return ok(event: TEST_EVENT, received: true) if event == TEST_EVENT
      return error(:bad_request, "unsupported event: #{event.inspect}") unless event == DECISION_EVENT
      return error(:bad_request, "missing certification object") unless certification.is_a?(Hash)
      return error(:unprocessable_entity, "unsupported status: #{decision_status.inspect}") unless Certification::Ship::EXTERNAL_DECISION_MAP.key?(decision_status)

      cert = Certification::Ship.find_by_external(uuid: certification[:id], external_id: certification[:externalId])
      return error(:not_found, "cert not found (externalId=#{certification[:externalId].inspect} id=#{certification[:id].inspect})") if cert.nil?
      return error(:bad_request, "missing or invalid timestamp") if decision_timestamp.nil?
      return error(:conflict, "implausible decision timestamp (timestamp=#{payload[:timestamp].inspect})") if cert.pending? && VerdictApplier.stale?(cert: cert, decided_at: decision_timestamp)

      if proof_video_url
        return error(:bad_request, "proofVideoUrl must be an http(s) URL") unless proof_video_url.match?(Certification::Ship::PROOF_VIDEO_URL_PATTERN)
        return error(:bad_request, "proofVideoUrl exceeds #{Certification::Ship::PROOF_VIDEO_URL_MAX_LENGTH} chars") if proof_video_url.length > Certification::Ship::PROOF_VIDEO_URL_MAX_LENGTH
      end

      apply(cert)
    end

    private

    attr_reader :payload

    def apply(cert)
      target_status = Certification::Ship::EXTERNAL_DECISION_MAP.fetch(decision_status)
      outcome = VerdictApplier.call(
        cert: cert,
        target_status: target_status,
        reviewer: reviewer,
        reviewer_slack_id: certification[:reviewerSlackId].to_s.presence,
        comment: reviewer_comment,
        proof_video_url: proof_video_url,
        external_uuid: certification[:id],
        decided_at: decision_timestamp
      )

      case outcome.status
      when :applied
        ok(decision_payload(outcome.cert, idempotent: false))
      when :idempotent
        ok(decision_payload(outcome.cert, idempotent: true))
      when :stale
        error(:conflict, "implausible decision timestamp (timestamp=#{payload[:timestamp].inspect})")
      when :divergent
        error(:conflict, "cert #{outcome.cert.id} is already #{outcome.cert.status} locally — refusing to apply remote #{decision_status}")
      else
        error(:internal_server_error, "unexpected verdict outcome: #{outcome.status.inspect}")
      end
    end

    def event
      payload[:event].to_s
    end

    def certification
      payload[:certification]
    end

    def decision_status
      certification[:status].to_s
    end

    def reviewer
      return @reviewer if defined?(@reviewer)
      slack_id = certification[:reviewerSlackId].to_s.presence
      user = slack_id && User.find_by(slack_id: slack_id)
      @reviewer = (user && !user.banned? && user.can_review?) ? user : nil
    end

    def decision_timestamp
      return @decision_timestamp if defined?(@decision_timestamp)
      @decision_timestamp = begin
        Time.iso8601(payload[:timestamp].to_s)
      rescue ArgumentError
        nil
      end
    end

    def reviewer_comment
      certification[:reviewerComment].to_s.presence&.truncate(Certification::Ship::FEEDBACK_MAX_LENGTH, omission: "")
    end

    def proof_video_url
      certification[:proofVideoUrl].to_s.presence
    end

    def decision_payload(cert, idempotent:)
      {
        idempotent: idempotent,
        ship_review: { id: cert.id, status: cert.status, project_id: cert.project_id, external_certification_id: cert.external_certification_id }
      }
    end

    def ok(body)
      Result.new(status: :ok, body: body)
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::DecisionProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end
  end
end
