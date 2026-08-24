# frozen_string_literal: true

# One decision handed down on a mission submission.
#
# A verdict is not durable on the submission itself: requesting a re-review
# (Projects::MissionResubmissionsController) clears reviewed_by, reviewed_at and
# rejection_message before sending the row back to pending, so an earlier
# rejection survives only in the PaperTrail version that cleared it. Reading the
# live columns alone would show a reviewer no sign the project has already been
# knocked back, which is the one thing they most need to know.
class Mission::Submission::Verdict
  DECIDED = %w[approved rejected].freeze

  attr_reader :submission, :status, :decided_at, :reviewer, :feedback

  def initialize(submission:, status:, decided_at:, reviewer:, feedback:)
    @submission = submission
    @status = status
    @decided_at = decided_at
    @reviewer = reviewer
    @feedback = feedback
  end

  # Every verdict a project has collected, newest first. `excluding` drops the
  # live verdict of the submission being reviewed, which is the decision in
  # progress rather than history, while keeping any verdict already erased from
  # that same submission.
  def self.history_for(project, excluding: nil)
    return [] if project.blank?

    submissions = project.mission_submissions.includes(:mission, :reviewed_by).to_a
    (live(submissions, excluding: excluding) + erased(submissions))
      .sort_by { |verdict| verdict.decided_at || Time.zone.at(0) }
      .reverse
  end

  def mission = submission&.mission

  def rejected? = status == "rejected"

  def self.live(submissions, excluding:)
    submissions.filter_map do |submission|
      next unless DECIDED.include?(submission.status)
      next if excluding&.persisted? && submission.id == excluding.id

      # reviewed_at is null on rows decided before it was stamped, so the sort
      # falls back to updated_at rather than dropping them to the bottom.
      new(submission: submission, status: submission.status,
          decided_at: submission.reviewed_at || submission.updated_at,
          reviewer: submission.reviewed_by, feedback: submission.rejection_message)
    end
  end
  private_class_method :live

  # Verdicts a re-review request wiped, rebuilt from the version that wiped
  # them. Versions per submission number in the handful, so they are filtered in
  # Ruby rather than reaching for jsonb operators.
  def self.erased(submissions)
    by_id = submissions.index_by(&:id)
    return [] if by_id.empty?

    states = PaperTrail::Version
               .where(item_type: Mission::Submission.name, item_id: by_id.keys.map(&:to_s))
               .order(:created_at)
               .filter_map { |version| cleared_verdict(version) }

    reviewers = User.where(id: states.map { |_id, before| before["reviewed_by_id"] }.uniq).index_by(&:id)
    states.map do |submission_id, before|
      new(submission: by_id[submission_id],
          status: before["status"],
          decided_at: parse_time(before["reviewed_at"]),
          reviewer: reviewers[before["reviewed_by_id"]],
          feedback: before["rejection_message"])
    end
  end
  private_class_method :erased

  # The row as it stood before a write that cleared a reviewer's verdict, paired
  # with its submission id. Requiring a reviewer keeps out certification
  # failures, which clear the same columns but were nobody's judgement (see
  # Post::ShipEvent#failed_certification?).
  def self.cleared_verdict(version)
    change = version.object_changes.is_a?(Hash) ? version.object_changes["reviewed_by_id"] : nil
    return unless change.is_a?(Array) && change.first.present? && change.last.nil?

    before = version.object
    return unless before.is_a?(Hash) && DECIDED.include?(before["status"])

    [ version.item_id.to_i, before ]
  end
  private_class_method :cleared_verdict

  def self.parse_time(value)
    value.presence && Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
  private_class_method :parse_time
end
