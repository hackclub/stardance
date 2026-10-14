module ExternalDashboard
  class FraudReportProcessor
    REQUIRED_FIELDS = %w[reported id reportedBy reason].freeze
    REPORT_REASON = "Shipwrights project flag".freeze
    FREE_TEXT_MAX_LENGTH = 10_000
    TEST_CONNECTION_ID = "test".freeze

    Result = Struct.new(:status, :body, keyword_init: true)

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = (payload || {}).with_indifferent_access
    end

    def call
      return ok_test if payload[:id].to_s == TEST_CONNECTION_ID
      return error(:bad_request, "missing required field: #{missing_field}") if missing_field
      return error(:bad_request, "invalid id: #{payload[:id].inspect}") if cert_id.nil?

      cert = ::Certification::Ship.find_by(id: cert_id)
      return error(:not_found, "cert not found (id=#{payload[:id].inspect})") if cert.nil?
      return ignored("project is deleted") if cert.project.nil? || cert.project.deleted_at.present?

      reporter = resolve_reporter
      return error(:unprocessable_entity, "no Stardance user found for reportedBy=#{payload[:reportedBy].inspect}") if reporter.nil?

      create_report!(cert, reporter)
    end

    private

    attr_reader :payload

    def missing_field
      REQUIRED_FIELDS.find { |field| payload[field].to_s.blank? }
    end

    def cert_id
      return @cert_id if defined?(@cert_id)
      raw = payload[:id].to_s
      @cert_id = raw.match?(Client::EXTERNAL_ID_PATTERN) ? raw.to_i : nil
    end

    def resolve_reporter
      slack_id = payload[:reportedBy].to_s.presence
      user = slack_id && User.find_by(slack_id: slack_id)
      (user && !user.banned? && user.can_review?) ? user : nil
    end

    def details
      payload[:reason].to_s.truncate(FREE_TEXT_MAX_LENGTH, omission: "")
    end

    def create_report!(cert, reporter)
      report = nil

      PaperTrail.request(whodunnit: reporter.id.to_s) do
        report = ::Project::Report.new(
          project_id: cert.project_id,
          reporter_id: reporter.id,
          reason: REPORT_REASON,
          details: details,
          status: :pending
        )
        report.save
      end

      if report.persisted?
        ok(report)
      else
        error(:unprocessable_entity, report.errors.full_messages.to_sentence)
      end
    rescue ActiveRecord::RecordNotUnique
      error(:unprocessable_entity, "this reviewer has already reported this project")
    end

    def ok(report)
      Result.new(status: :ok, body: { status: "ok", report_id: report.id })
    end

    def ok_test
      Result.new(status: :ok, body: { status: "ok", test: true })
    end

    def ignored(reason)
      Rails.logger.warn "[ExternalDashboard::FraudReportProcessor] ignored report: #{reason}"
      Result.new(status: :ok, body: { ignored: reason })
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::FraudReportProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end
  end
end
