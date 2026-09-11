# A verdict reached on the per-person fraud page (admin/fraud/subjects) settles
# one item and leaves the reviewer where they were, instead of bouncing them
# back to a queue the way each source's own dashboard does. The verdict itself
# still goes through that dashboard's action, so authorization and the
# PaperTrail trail are the same wherever it was submitted from.
module FraudSubjectVerdict
  extend ActiveSupport::Concern

  included do
    before_action :enforce_fraud_subject_claim, if: -> { params[:fraud_subject_id].present? }
  end

  private

  # Turbo processes a stream response wherever it came from, so this reaches
  # the reviewer whichever item's frame they submitted from.
  def enforce_fraud_subject_claim
    return unless fraud_subject_claim_lost?

    render turbo_stream: turbo_stream.replace(
      "fraud-subject-claim",
      partial: "admin/fraud/subjects/claim",
      locals: { claim: FraudSubjectClaim.active.find_by(subject_id: fraud_subject.id), lost: true }
    ), status: :conflict
  end

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
  # The claim is enforced here rather than only hidden in the view: a stale tab
  # left open past the hour must not be able to land a verdict on someone
  # another reviewer has since taken.
  def fraud_subject_claim_lost?
    fraud_subject.present? && FraudSubjectClaim.held_by_other?(fraud_subject, current_user)
  end

  def render_fraud_subject_verdict(record, note, refresh_integrity: false)
    render turbo_stream: fraud_subject_verdict_streams([ [ record, note ] ], refresh_integrity: refresh_integrity)
  end

  # A bulk action settles a whole pile in one submission. Each item is swapped
  # and claimed exactly as it would have been one at a time, so the reviewer is
  # paid the same either way.
  def render_fraud_subject_verdicts(settled)
    render turbo_stream: fraud_subject_verdict_streams(settled)
  end

  def fraud_subject_verdict_streams(settled, refresh_integrity: false)
    streams = []
    records = settled.map(&:first)

    if refresh_integrity
      streams << turbo_stream.replace(
        "fraud-subject-integrity-items",
        partial: "admin/fraud/subjects/integrity_items",
        locals: { user: fraud_subject }
      )

      # The siblings the cascade settled leave the list above on their own, but
      # their slots in the progress bar would sit there still waiting.
      Admin::Fraud::SubjectQueue.cascaded_siblings_of(records.first, user: fraud_subject).each do |sibling|
        streams << turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(sibling, :progress),
          partial: "admin/fraud/subjects/progress_slot",
          locals: { record: sibling }
        )
      end
    else
      settled.each do |record, note|
        streams << turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(record),
          partial: "admin/fraud/subjects/resolved_item",
          locals: { record: record, note: note }
        )
      end
    end

    streams << turbo_stream.replace(
      "fraud-subject-counts",
      partial: "admin/fraud/subjects/counts",
      locals: { user: fraud_subject }
    )

    # A settled order leaves the bulk buttons offering work that is no longer
    # there, so they are re-read alongside the counts.
    streams << turbo_stream.replace(
      "fraud-subject-order-bulk-actions",
      partial: "admin/fraud/subjects/order_bulk_actions",
      locals: { user: fraud_subject }
    )

    records.each do |record|
      streams << turbo_stream.replace(
        ActionView::RecordIdentifier.dom_id(record, :progress),
        partial: "admin/fraud/subjects/progress_slot",
        locals: { record: record }
      )
    end

    cleared = fraud_subject_cleared?
    payout = fraud_subject_payout_for(records, cleared: cleared)

    if payout
      payout.complete! if cleared && payout.completed_at.nil?
      streams << turbo_stream.replace(
        "fraud-subject-payout",
        partial: "admin/fraud/subjects/payout",
        locals: { payout: payout }
      )

      if payout.completed_at
        streams << turbo_stream.replace(
          "fraud-subject-celebration",
          partial: "admin/fraud/subjects/celebration",
          locals: { payout: payout, total: FraudReviewPayout.unpaid.where(reviewer: current_user).sum(:amount) }
        )
      end
    end

    # Keyed off the queue rather than the payout: the person is finished even
    # when the last item was already claimed and earned nothing further.
    if cleared
      streams << turbo_stream.replace(
        "fraud-subject-next",
        partial: "admin/fraud/subjects/next_subject",
        locals: {
          cleared: true,
          next_subject_id: Admin::Fraud::SubjectQueue.next_subject_id(reviewer: current_user, after: fraud_subject)
        }
      )
    end

    streams << turbo_stream.update("flash-region", partial: "shared/flash") if flash.any?

    streams
  end

  # Every settled item is claimed; they all land on the one open tally, so the
  # last claim is that tally with the full run of them counted.
  #
  # An item another payout already claimed earns nothing further but can still
  # be the one that empties the queue, and a tally left open is never payable
  # (FraudReviewPayout.payable), so the open one is picked up in that case
  # rather than left to sit unpaid.
  def fraud_subject_payout_for(records, cleared:)
    claimed = records.filter_map do |record|
      FraudReviewPayout.claim!(record, reviewer: current_user, subject: fraud_subject)
    end

    claimed.last || (cleared ? FraudReviewPayout.unpaid.find_by(reviewer: current_user, subject: fraud_subject, completed_at: nil) : nil)
  end

  # A cascading integrity verdict settles siblings this request never touched,
  # so the queue is re-read rather than inferred from the item just decided.
  def fraud_subject_cleared?
    Admin::Fraud::SubjectQueue.flags_for(fraud_subject).none? &&
      Admin::Fraud::SubjectQueue.orders_for(fraud_subject).none? &&
      Admin::Fraud::SubjectQueue.integrity_checks_for(fraud_subject).none?
  end

  # For a change that leaves the item in the queue, like putting an order on
  # hold: the row is re-rendered in place rather than swapped for a note.
  def render_fraud_subject_item(record, partial:)
    render turbo_stream: turbo_stream.replace(
      ActionView::RecordIdentifier.dom_id(record),
      partial: partial,
      object: record,
      locals: { user: fraud_subject }
    )
  end
end
