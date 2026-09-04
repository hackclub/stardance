# A verdict reached on the per-person fraud page (admin/fraud/subjects) settles
# one item and leaves the reviewer where they were, instead of bouncing them
# back to a queue the way each source's own dashboard does. The verdict itself
# still goes through that dashboard's action, so authorization and the
# PaperTrail trail are the same wherever it was submitted from.
module FraudSubjectVerdict
  extend ActiveSupport::Concern

  private

  # Present only on submissions from the fraud page, which is what marks a
  # request as one that should answer with a swap rather than a redirect.
  def fraud_subject
    return if params[:fraud_subject_id].blank?

    @fraud_subject ||= User.find(params[:fraud_subject_id])
  end

  # `refresh_integrity` re-renders the whole integrity list rather than the one
  # settled row: a banned or manually-passed verdict cascades onto the
  # project's other pending checks (Certification::Integrity::CASCADING_STATUSES),
  # so its siblings on screen are stale too.
  def render_fraud_subject_verdict(record, note, refresh_integrity: false)
    streams = []

    if refresh_integrity
      streams << turbo_stream.replace(
        "fraud-subject-integrity-items",
        partial: "admin/fraud/subjects/integrity_items",
        locals: { user: fraud_subject }
      )
    else
      streams << turbo_stream.replace(
        ActionView::RecordIdentifier.dom_id(record),
        partial: "admin/fraud/subjects/resolved_item",
        locals: { record: record, note: note }
      )
    end

    streams << turbo_stream.replace(
      "fraud-subject-counts",
      partial: "admin/fraud/subjects/counts",
      locals: { user: fraud_subject }
    )

    render turbo_stream: streams
  end
end
