# == Schema Information
#
# Table name: project_reports
#
#  id          :bigint           not null, primary key
#  details     :text             not null
#  reason      :string           not null
#  status      :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  project_id  :bigint           not null
#  reporter_id :bigint           not null
#
# Indexes
#
#  idx_project_reports_status_created_at_desc           (status,created_at DESC)
#  index_project_reports_on_project_id                  (project_id)
#  index_project_reports_on_reporter_id                 (reporter_id)
#  index_project_reports_on_reporter_id_and_project_id  (reporter_id,project_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reporter_id => users.id)
#
class Project::Report < ApplicationRecord
    has_paper_trail

    belongs_to :reporter, class_name: "User"
    belongs_to :project
    after_commit :notify_slack_channel, on: :create

    REASONS = [
      "low_effort",
      "undeclared_ai",
      "demo_broken",
      "fraud",
      "other",
      "External flag",
      "YSWS project flag",
      "Shipwrights project flag"
    ].freeze
    USER_REASONS = %w[low_effort undeclared_ai demo_broken other].freeze # fraud is internal

    DETAILS_MIN_LENGTH = 20

    # These four never save a Project::Report row — Slack-only ping instead.
    # The other three stay in REASONS/USER_REASONS (unlike this one) so admin
    # views can still filter historical rows.
    SHOULD_NOT_HAVE_BEEN_APPROVED_REASON = "should_not_have_been_approved"
    SLACK_ONLY_REASONS = [ "low_effort", "undeclared_ai", "demo_broken", SHOULD_NOT_HAVE_BEEN_APPROVED_REASON ].freeze
    SHOULD_NOT_HAVE_BEEN_APPROVED_CHANNEL =
      Rails.application.credentials.dig(:slack, :should_not_have_been_approved_channel) ||
      ENV["SHOULD_NOT_HAVE_BEEN_APPROVED_SLACK_CHANNEL"] ||
      "C09TTRZH94Z"
    SHOULD_NOT_HAVE_BEEN_APPROVED_DETAILS_MAX_LENGTH = 2_000
    SHOULD_NOT_HAVE_BEEN_APPROVED_THROTTLE = 7.days

    enum :status, { pending: 0, reviewed: 1, dismissed: 2 }, default: :pending

    validates :reason, presence: true, inclusion: { in: REASONS }
    validates :details, presence: true, length: { minimum: DETAILS_MIN_LENGTH }
    validates :reporter_id, uniqueness: { scope: :project_id, message: "has already reported this project" }

    validates :reporter, exclusion: {
        in: ->(report) { report.project&.users || [] },
        message: "cannot report own project"
      }, unless: -> { Rails.env.development? || reason == "fraud" }

    REASON_LABELS = {
      "low_effort" => "Low-effort project",
      "undeclared_ai" => "Uses AI but it's undeclared",
      "demo_broken" => "Demo does not work",
      "other" => "Other",
      SHOULD_NOT_HAVE_BEEN_APPROVED_REASON => "Project should not have been approved"
    }.freeze

    def reason_label
      REASON_LABELS.fetch(reason, reason.humanize)
    end

    # Returns :ok, :details_too_short, :not_allowed, :not_approved, or :throttled.
    def self.flag_via_slack!(project:, reporter:, details:, reason:)
      details = details.to_s.strip
      return :details_too_short if details.length < DETAILS_MIN_LENGTH
      return :not_allowed if !Rails.env.development? && project.users.include?(reporter)

      latest_approval = project.ship_reviews.approved.order(Arel.sql("decided_at DESC NULLS LAST"), id: :desc).first
      return :not_approved if reason == SHOULD_NOT_HAVE_BEEN_APPROVED_REASON && latest_approval.nil?

      # exists? checked before write so a cache outage fails open, not throttled.
      cache_scope = reason == SHOULD_NOT_HAVE_BEEN_APPROVED_REASON ? latest_approval.id : project.id
      cache_key = "project_report/slack_flag/#{reason}/#{cache_scope}/#{reporter.id}"
      return :throttled if Rails.cache.exist?(cache_key)
      Rails.cache.write(cache_key, true, expires_in: SHOULD_NOT_HAVE_BEEN_APPROVED_THROTTLE)

      reviewer = latest_approval&.reviewer

      Rails.logger.info(
        "[Project::Report] slack_flag (#{reason}): project=#{project.id} reporter=#{reporter.id} reviewer=#{reviewer&.id || 'none'}"
      )

      SendSlackDmJob.perform_later(
        SHOULD_NOT_HAVE_BEEN_APPROVED_CHANNEL,
        "Project flagged",
        blocks_path: "notifications/reports/project_flagged_slack_message",
        locals: {
          project: project,
          reporter: reporter,
          reviewer: reviewer,
          reason_label: REASON_LABELS.fetch(reason, reason.humanize),
          details: details.truncate(SHOULD_NOT_HAVE_BEEN_APPROVED_DETAILS_MAX_LENGTH, omission: "")
        },
        unfurl_links: false,
        unfurl_media: false
      )
      :ok
    end

    private

    def notify_slack_channel
      SendSlackDmJob.perform_later("C0A1YJ9PDAS", "New report received", blocks_path: "notifications/reports/slack_message", locals: { report: self })
    end
end
