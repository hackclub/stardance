class Certification::PermanentRejectionNomination < ApplicationRecord
  self.table_name = "certification_permanent_rejection_nominations"

  belongs_to :project, -> { with_deleted }
  belongs_to :reviewable, polymorphic: true
  belongs_to :reviewer, class_name: "User"
  belongs_to :decided_by, class_name: "User", optional: true
  has_paper_trail

  enum :status, { pending: 0, approved: 1, denied: 2 }, default: :pending
  scope :blocking, -> { where(status: [ :pending, :approved ]) }

  normalizes :reason, with: ->(value) { value&.strip }
  validates :reason, presence: true, length: { maximum: 10_000 }
  validates :reviewable_type, inclusion: { in: %w[Certification::FundingRequest Certification::Ship] }
  validate :hardware_review_matches_project

  after_create_commit :post_nomination_to_staff!

  # Keep the public review pending. Releasing the claim also increments its
  # optimistic lock, invalidating verdict forms opened before this nomination.
  def self.nominate!(review:, reviewer:, reason:)
    nomination = new(project: review.project, reviewable: review, reviewer: reviewer, reason: reason)
    review.with_lock do
      review.project.with_lock do
        unless review.pending? && review.claim_held_by?(reviewer) && !review.project.hardware_review_blocked?
          nomination.errors.add(:base, "This review is no longer available. Reload the review before continuing.")
          raise ActiveRecord::RecordInvalid, nomination
        end
        nomination.save!
        review.update!(reviewer: nil, claimed_at: nil, claim_expires_at: nil)
        nomination.decide!(admin: reviewer, approve: true) if reviewer.admin?
      end
    end
    nomination
  end

  # Lock in the same order as nomination/verdicts: review, then project. A
  # repeated or competing decision must not send another builder notification.
  def decide!(admin:, approve:)
    raise Pundit::NotAuthorizedError unless admin&.admin? && !project.memberships.exists?(user_id: admin.id)

    reviewable.with_lock do
      project.with_lock do
        reload
        if approve && project.deleted?
          errors.add(:base, "This project has been deleted. Deny the nomination to close it without notifying the builder.")
          raise ActiveRecord::RecordInvalid, self
        end
        unless pending? && reviewable.pending?
          errors.add(:base, "This nomination has already been decided or the review is no longer pending.")
          raise ActiveRecord::RecordInvalid, self
        end

        update!(status: approve ? :approved : :denied, decided_by: admin, decided_at: Time.current)
        if approve
          reviewable.update!(status: :permanently_rejected, feedback: reason, reviewer: admin,
                             claimed_at: nil, claim_expires_at: nil)
        else
          reviewable.update!(reviewer: nil, claimed_at: nil, claim_expires_at: nil)
        end
      end
    end
  end

  def review_stage
    reviewable_type == "Certification::FundingRequest" ? "Design" : "Build"
  end

  private

  def hardware_review_matches_project
    unless project&.hardware? && reviewable&.project_id == project_id
      errors.add(:base, "Only a review of this hardware project can be nominated.")
    end
  end

  def post_nomination_to_staff!
    routes = Rails.application.routes.url_helpers
    url_opts = (Rails.application.config.action_controller.default_url_options || {})
      .reverse_merge(host: "stardance.hackclub.com", protocol: "https")
    SendSlackDmJob.perform_later(
      Certification::Reviewable::HARDWARE_APPROVAL_FEED_CHANNEL,
      nil,
      blocks_path: "notifications/hardware/permanent_rejection_nominated",
      locals: {
        project_title: project.title,
        nomination_url: routes.admin_certification_permanent_rejection_nomination_url(self, **url_opts),
        reviewer_name: reviewer.display_name,
        review_stage: review_stage,
        reason: reason,
        automatically_approved: approved?
      }
    )
  rescue StandardError => e
    Rails.logger.error("PermanentRejectionNomination ##{id} staff notification failed: #{e.message}")
    Sentry.capture_exception(e)
  end
end
