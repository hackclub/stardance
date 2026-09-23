# == Schema Information
#
# Table name: certification_second_stage_reviews
#
#  id                    :bigint           not null, primary key
#  approved_amount_cents :integer
#  claim_expires_at      :datetime
#  claimed_at            :datetime
#  decided_at            :datetime
#  feedback              :text
#  internal_reason       :text
#  lock_version          :integer          default(0), not null
#  reviewable_type       :string           not null
#  stardust_earned       :integer
#  status                :integer          default(0), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  reviewable_id         :bigint           not null
#  reviewer_id           :bigint
#
# Indexes
#
#  idx_second_stage_reviews_on_status_claim_expires         (status,claim_expires_at)
#  index_certification_second_stage_reviews_on_decided_at   (decided_at)
#  index_certification_second_stage_reviews_on_reviewable   (reviewable_type,reviewable_id)
#  index_certification_second_stage_reviews_on_reviewer_id  (reviewer_id)
#  index_second_stage_reviews_unique_reviewable             (reviewable_type,reviewable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (reviewer_id => users.id)
#
module Certification
  # The second (T2) stage of a hardware review. A T1 approval opens one; only
  # approving it here runs the payout. Its own record, not a T1 status, so the
  # T1 enum (stats, undo, decision API) stays untouched.
  class SecondStageReview < ApplicationRecord
    self.table_name = "certification_second_stage_reviews"

    include Certification::Reviewable

    belongs_to :reviewable, polymorphic: true
    belongs_to :reviewer, class_name: "User", optional: true

    has_paper_trail

    enum :status, {
      pending: 0,
      approved: 1,
      returned: 2
    }, default: :pending

    REVIEW_BOUNTY = 1

    SLA_DAYS = 3

    VERDICTS = %w[approved returned].freeze

    has_many_attached :feedback_images do |attachable|
      attachable.variant :thumb, resize_to_limit: [ 320, 320 ], format: :webp
    end

    validates :feedback, length: { maximum: 10_000 }, allow_blank: true
    # A return replaces the T1 feedback the builder sees, so it must say why.
    validates :feedback, presence: true, if: :returned?
    validates :reviewable_type, inclusion: { in: %w[Certification::FundingRequest Certification::Ship] }

    # T2 override of the grant; nil pays the T1 figure (FundingRequest#payable_amount_cents).
    validates :approved_amount_cents,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              allow_nil: true
    validate :amount_only_on_design_stage
    validate :amount_within_tier_max

    delegate :project, :owner, to: :reviewable

    # Not `build`: that's already an Active Record class method.
    scope :design_stage, -> { where(reviewable_type: "Certification::FundingRequest") }
    scope :build_stage, -> { where(reviewable_type: "Certification::Ship") }

    scope :for_stage, ->(stage) { stage.to_s == "design" ? design_stage : build_stage }

    scope :for_project, ->(project_id) {
      where(
        "(reviewable_type = 'Certification::FundingRequest' AND reviewable_id IN (:funding)) OR " \
        "(reviewable_type = 'Certification::Ship' AND reviewable_id IN (:ships))",
        funding: Certification::FundingRequest.where(project_id: project_id).select(:id),
        ships: Certification::Ship.where(project_id: project_id).select(:id)
      )
    }

    # A T2 reviewer never clears their own T1 verdict or their own project. This
    # table's reviewer_id is the claim holder, so it's deliberately not excluded.
    scope :for_reviewer, ->(user) {
      where.not(id: reviewed_at_t1_by(user))
        .where.not(id: on_projects_of(user))
    }

    def self.reviewed_at_t1_by(user)
      funding = where(reviewable_type: "Certification::FundingRequest")
        .joins("INNER JOIN certification_funding_requests ON certification_funding_requests.id = certification_second_stage_reviews.reviewable_id")
        .where(certification_funding_requests: { reviewer_id: user.id })
      ships = where(reviewable_type: "Certification::Ship")
        .joins("INNER JOIN certification_ship_reviews ON certification_ship_reviews.id = certification_second_stage_reviews.reviewable_id")
        .where(certification_ship_reviews: { reviewer_id: user.id })

      funding.select(:id).to_a.map(&:id) + ships.select(:id).to_a.map(&:id)
    end

    def self.on_projects_of(user)
      project_ids = user.memberships.select(:project_id)
      funding = where(reviewable_type: "Certification::FundingRequest")
        .joins("INNER JOIN certification_funding_requests ON certification_funding_requests.id = certification_second_stage_reviews.reviewable_id")
        .where(certification_funding_requests: { project_id: project_ids })
      ships = where(reviewable_type: "Certification::Ship")
        .joins("INNER JOIN certification_ship_reviews ON certification_ship_reviews.id = certification_second_stage_reviews.reviewable_id")
        .where(certification_ship_reviews: { project_id: project_ids })

      funding.select(:id).to_a.map(&:id) + ships.select(:id).to_a.map(&:id)
    end

    # Fraud-flagged projects stay out of "next", same as the T1 queues.
    def self.available_for(user)
      super.merge(for_reviewer(user))
        .where.not(id: for_project(fraud_flagged_project_ids).select(:id))
    end

    def self.next_eligible_scope(user)
      available_for(user).not_skipped_by(user)
    end

    # Idempotent: a re-approval after an undo rewinds the existing row, clearing
    # the last verdict's amount and notes.
    def self.open_for!(reviewable)
      record = find_or_initialize_by(reviewable: reviewable)
      record.assign_attributes(
        status: :pending,
        reviewer_id: nil,
        claimed_at: nil,
        claim_expires_at: nil,
        decided_at: nil,
        approved_amount_cents: nil,
        feedback: nil,
        internal_reason: nil,
        stardust_earned: nil
      )
      record.save!
      record
    end

    def stage = reviewable.is_a?(Certification::FundingRequest) ? "design" : "build"
    def stage_label = stage == "design" ? "Design" : "Build"

    def first_stage_reviewer = reviewable.reviewer

    def approved_amount_dollars
      approved_amount_cents ? approved_amount_cents / 100 : nil
    end

    def approved_amount_dollars=(value)
      self.approved_amount_cents = value.presence && (value.to_d * 100).to_i
    end

    def verdict = decided? ? status : nil

    def verdict=(value)
      self.status = value if VERDICTS.include?(value.to_s)
    end

    before_save :stamp_claimed_at,
      if: -> { will_save_change_to_reviewer_id? && reviewer_id.present? && claimed_at.nil? }
    before_save :stamp_decided_at,
      if: -> { will_save_change_to_status? && status_change&.last.in?(DECIDED_STATUSES) && decided_at.nil? }
    before_save :assign_stardust_earned,
      if: -> { will_save_change_to_status? && status_change&.last.in?(DECIDED_STATUSES) && reviewer_id.present? }
    # A return applies inside the transaction; the release calls HCB, so it waits
    # for the commit or a rollback could lose the grant id and pay twice.
    after_save :return_reviewable!, if: -> { saved_change_to_status? && returned? }
    after_save_commit :release_reviewable!, if: -> { saved_change_to_status? && approved? }

    def notification_locals = reviewable.notification_locals

    def queue_mismatch_flagged_label = "#{stage} second stage"
    def queue_mismatch_suggested_label = "first stage"

    private

    def amount_only_on_design_stage
      return if approved_amount_cents.blank? || stage == "design"

      errors.add(:approved_amount_cents, "only applies to a design review")
    end

    # The override can't be a way around T1's tier cap.
    def amount_within_tier_max
      return if approved_amount_cents.blank? || stage != "design"

      max = reviewable.tier_max_cents
      return if max.nil? || approved_amount_cents <= max

      errors.add(:approved_amount_cents, "exceeds the #{reviewable.tier_label} maximum of $#{reviewable.tier_max_dollars}")
    end

    def stamp_claimed_at
      self.claimed_at = Time.current
    end

    def stamp_decided_at
      self.decided_at = Time.current
    end

    def assign_stardust_earned
      self.stardust_earned = REVIEW_BOUNTY
    end

    def release_reviewable!
      reviewable.release_second_stage!
    end

    def return_reviewable!
      reviewable.return_from_second_stage!(feedback: feedback)
    end
  end
end
