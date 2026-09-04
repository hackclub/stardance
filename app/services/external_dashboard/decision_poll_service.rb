module ExternalDashboard
  # No persisted watermark on purpose: the window just slides a fixed
  # lookback behind "now" every run, so a missed run is caught by the next
  # one instead of depending on a cursor that could get lost.
  class DecisionPollService
    LOOKBACK = 2.hours
    UNHEALTHY_ALERT_TTL = 1.hour

    def self.call(...) = new(...).call

    def initialize(lookback: LOOKBACK, now: Time.current, dry_run: false)
      @lookback = lookback
      @now = now
      @dry_run = dry_run
    end

    def call
      result = ShipsClient.fetch_all(updated_since: now - lookback, status: "all")
      counts = Hash.new(0)

      result.ships.each { |ship| counts[process(ship)] += 1 }

      tag = dry_run ? " [dry-run]" : ""
      Rails.logger.info "[ExternalDashboard::DecisionPollService]#{tag} fetch=#{result.status} fetched=#{result.ships.size} #{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}"
      alert_on_unhealthy_run(result, counts) unless dry_run
      counts.merge(fetch_status: result.status)
    end

    private

    attr_reader :lookback, :now, :dry_run

    UNRESOLVED_OUTCOMES = %i[missing_timestamp not_found error].freeze

    def alert_on_unhealthy_run(result, counts)
      unless result.status == :ok
        AlertThrottle.once("external_dashboard:decision_poll:fetch_unhealthy:#{result.status}", ttl: UNHEALTHY_ALERT_TTL) do
          Sentry.capture_message(
            "ExternalDashboard::DecisionPollService fetch did not complete",
            level: :warning,
            extra: { fetch_status: result.status, fetch_error: result.error, fetched: result.ships.size }
          )
        end
        return
      end

      decided_count = result.ships.size - counts[:ignored_status]
      return if decided_count <= 0

      unresolved_count = UNRESOLVED_OUTCOMES.sum { |outcome| counts[outcome] }
      return if unresolved_count < decided_count * 0.5

      AlertThrottle.once("external_dashboard:decision_poll:high_error_rate", ttl: UNHEALTHY_ALERT_TTL) do
        Sentry.capture_message(
          "ExternalDashboard::DecisionPollService is failing to apply most decided ships in its window",
          level: :warning,
          extra: { fetched: result.ships.size, decided: decided_count, unresolved: unresolved_count, breakdown: counts }
        )
      end
    end

    def process(ship)
      status = ship["status"].to_s
      target = Certification::Ship::EXTERNAL_DECISION_MAP[status]
      return :ignored_status unless target

      decided_at = parse_time(ship["decidedAt"])
      return :missing_timestamp unless decided_at

      cert = Certification::Ship.find_by_external(uuid: ship["id"], external_id: ship["externalId"])
      return :not_found unless cert
      return :ignored if cert.project.nil? || cert.project.deleted_at.present? || cert.owner&.banned?

      proof_video_url = ship.dig("links", "proofVideo").presence
      return :invalid if proof_video_url && !valid_proof_video_url?(proof_video_url)

      apply(ship, cert, target, proof_video_url, decided_at).status
    rescue StandardError => e
      Rails.logger.warn "[ExternalDashboard::DecisionPollService] ship=#{ship['id'].inspect} #{e.class}: #{e.message}"
      :error
    end

    def apply(ship, cert, target, proof_video_url, decided_at)
      reviewer_slack_id = ship.dig("reviewer", "slackId").to_s.presence
      VerdictApplier.call(
        cert: cert,
        target_status: target,
        reviewer: resolve_reviewer(reviewer_slack_id),
        reviewer_slack_id: reviewer_slack_id,
        comment: ship["feedback"].to_s.presence&.truncate(Certification::Ship::FEEDBACK_MAX_LENGTH, omission: ""),
        proof_video_url: proof_video_url,
        external_uuid: ship["id"],
        decided_at: decided_at,
        dry_run: dry_run
      )
    end

    def valid_proof_video_url?(url)
      url.match?(Certification::Ship::PROOF_VIDEO_URL_PATTERN) && url.length <= Certification::Ship::PROOF_VIDEO_URL_MAX_LENGTH
    end

    def resolve_reviewer(slack_id)
      return nil if slack_id.blank?

      user = User.find_by(slack_id: slack_id)
      user && !user.banned? && user.can_review? ? user : nil
    end

    def parse_time(iso8601)
      iso8601.present? ? Time.iso8601(iso8601) : nil
    rescue ArgumentError
      nil
    end
  end
end
