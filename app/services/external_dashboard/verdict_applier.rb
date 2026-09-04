module ExternalDashboard
  # Shared by the inbound decision webhook and the reconciliation poller, so
  # there's one implementation of the lock/idempotency/divergence logic.
  class VerdictApplier
    REPLAY_CLOCK_SKEW = 5.minutes
    DIVERGENCE_SENTRY_MESSAGE = "ExternalDashboard verdict diverges from local decision".freeze
    DIVERGENCE_ALERT_TTL = 1.day

    Outcome = Struct.new(:status, :cert, keyword_init: true)

    def self.call(...) = new(...).call

    def self.stale?(cert:, decided_at:)
      return false if decided_at.blank?

      decided_at < (cert.created_at - REPLAY_CLOCK_SKEW) || decided_at > (Time.current + REPLAY_CLOCK_SKEW)
    end

    def initialize(cert:, target_status:, reviewer: nil, reviewer_slack_id: nil, comment: nil, proof_video_url: nil, external_uuid: nil, decided_at: nil, dry_run: false)
      @cert = cert
      @target_status = target_status
      @reviewer = reviewer
      @reviewer_slack_id = reviewer_slack_id
      @comment = comment
      @proof_video_url = proof_video_url
      @external_uuid = external_uuid
      @decided_at = decided_at
      @dry_run = dry_run
    end

    def call
      outcome = nil
      PaperTrail.request(whodunnit: whodunnit) do
        ActiveRecord::Base.transaction(requires_new: true) do
          cert.with_lock { outcome = apply_locked }
          raise ActiveRecord::Rollback if dry_run
        end
      end
      outcome
    end

    private

    attr_reader :cert, :target_status, :reviewer, :reviewer_slack_id, :comment, :proof_video_url, :external_uuid, :decided_at, :dry_run

    def apply_locked
      return stale_outcome if cert.pending? && self.class.stale?(cert: cert, decided_at: decided_at)

      if cert.pending?
        apply!
        Outcome.new(status: :applied, cert: cert)
      elsif cert.status.to_sym == target_status
        cert.assign_external_certification_id!(external_uuid)
        Outcome.new(status: :idempotent, cert: cert)
      else
        log_divergence
        Outcome.new(status: :divergent, cert: cert)
      end
    end

    def apply!
      reason = record_only_reason
      cert.record_verdict_only = reason.present?
      cert.update!(status: target_status, feedback: comment, reviewer_id: reviewer&.id, proof_video_url: proof_video_url, decided_at: decided_at)
      cert.assign_external_certification_id!(external_uuid)
      reason ? log_record_only(reason) : log_dropped_reviewer
    end

    # Both of these used to drop the verdict on the floor, which left the cert pending
    # here forever while the dashboard had it decided - and the poller re-skipped it on
    # every run, so nothing ever reconciled it. Record the status, skip what's downstream.
    def record_only_reason
      return "project deleted" if cert.project.nil? || cert.project.deleted_at.present?
      return "owner banned" if cert.owner&.banned?

      nil
    end

    def log_record_only(reason)
      Rails.logger.info "[ExternalDashboard::VerdictApplier]#{dry_run_tag} cert=#{cert.id} verdict recorded only (#{reason})"
    end

    def log_dropped_reviewer
      return if reviewer || reviewer_slack_id.blank?

      Rails.logger.warn "[ExternalDashboard::VerdictApplier]#{dry_run_tag} cert=#{cert.id} reviewerSlackId=#{reviewer_slack_id} did not resolve to a local reviewer - stardust not awarded"
    end

    def stale_outcome
      Rails.logger.warn "[ExternalDashboard::VerdictApplier]#{dry_run_tag} cert=#{cert.id} implausible decision timestamp (decided_at=#{decided_at})"
      Outcome.new(status: :stale, cert: cert)
    end

    def log_divergence
      Rails.logger.warn "[ExternalDashboard::VerdictApplier]#{dry_run_tag} cert=#{cert.id} already #{cert.status} locally — refusing remote #{target_status}"
      return if dry_run

      # The poller re-checks every cert in its lookback window on every run, so
      # an unresolved divergence would otherwise re-page on every cycle.
      AlertThrottle.once("external_dashboard:verdict_applier:divergence:#{cert.id}:#{cert.status}:#{target_status}", ttl: DIVERGENCE_ALERT_TTL) do
        Sentry.capture_message(
          DIVERGENCE_SENTRY_MESSAGE,
          level: :warning,
          extra: { cert_id: cert.id, local_status: cert.status, remote_status: target_status.to_s }
        )
      end
    end

    def dry_run_tag
      dry_run ? " [dry-run]" : ""
    end

    def whodunnit
      reviewer&.id&.to_s || "external_dashboard"
    end
  end
end
