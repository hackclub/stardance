# == Schema Information
#
# Table name: certification_integrities
#
#  id                     :bigint           not null, primary key
#  claimed_at             :datetime
#  decision_justification :text
#  deduction_minutes      :integer
#  flags                  :integer          default(0), not null
#  fraud_detection_data   :jsonb
#  reviewed_at            :datetime
#  status                 :integer          default("auto_passed"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  claimed_by_id          :bigint
#  reviewer_id            :bigint
#  ship_event_id          :bigint           not null
#
# Indexes
#
#  index_certification_integrities_on_claimed_by_id  (claimed_by_id)
#  index_certification_integrities_on_reviewer_id    (reviewer_id)
#  index_certification_integrities_on_ship_event_id  (ship_event_id) UNIQUE
#  index_certification_integrities_on_status         (status)
#
# Foreign Keys
#
#  fk_rails_...  (claimed_by_id => users.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#
module Certification
  class Integrity < ApplicationRecord
    self.table_name = "certification_integrities"

    belongs_to :ship_event, class_name: "Post::ShipEvent", inverse_of: :integrity_check
    belongs_to :reviewer, class_name: "User", optional: true
    belongs_to :claimed_by, class_name: "User", optional: true

    delegate :project, to: :ship_event

    # The user who shipped — author of the ship event's post.
    def user = ship_event&.post&.user

    has_paper_trail

    enum :status, {
      auto_passed: 0,
      pending: 1,
      banned: 2,
      deducted: 3,
      manually_passed: 4
    }, default: :auto_passed

    DECIDED_STATUSES = %w[banned deducted manually_passed].freeze

    # How long a reviewer's claim on a review holds before it's up for grabs
    # again. There's no separate expiry column — expiry is just claimed_at + TTL.
    CLAIM_TTL = 20.minutes

    # A review is visible to a reviewer if nobody holds an active claim on it,
    # or they're the one holding it.
    scope :unclaimed_or_claimed_by, ->(user) {
      where("claimed_by_id IS NULL OR claimed_at IS NULL OR claimed_at < :expired OR claimed_by_id = :user_id",
            expired: CLAIM_TTL.ago, user_id: user.id)
    }

    # Claims (or refreshes an existing claim on) a pending review for the given
    # user, unless someone else already holds an active claim on it. Conditioned
    # atomically in the UPDATE itself so two reviewers opening the same review at
    # once can't both win the claim. Returns the claimed record, or nil if
    # another reviewer's claim is still active.
    def self.atomic_claim!(record_id, user)
      now = Time.current
      updated = pending.where(id: record_id)
        .where("claimed_by_id IS NULL OR claimed_at IS NULL OR claimed_at < :expired OR claimed_by_id = :user_id",
               expired: CLAIM_TTL.ago, user_id: user.id)
        .update_all(claimed_by_id: user.id, claimed_at: now, updated_at: now)
      updated.zero? ? nil : find(record_id)
    end

    FLAG_UNKNOWN_FILE      = 1 << 0
    FLAG_CURSOR_STRANGE    = 1 << 1
    FLAG_NEURALNET         = 1 << 2
    FLAG_NO_HACKATIME_USER = 1 << 3
    FLAG_CHECK_FAILED      = 1 << 4

    FLAGS_BY_BIT = {
      FLAG_UNKNOWN_FILE      => :unknown_file,
      FLAG_CURSOR_STRANGE    => :cursor_strange,
      FLAG_NEURALNET         => :neuralnet,
      FLAG_NO_HACKATIME_USER => :no_hackatime_user,
      FLAG_CHECK_FAILED      => :check_failed
    }.freeze

    validates :decision_justification, length: { maximum: 10_000 }, allow_blank: true
    validates :reviewer_id, presence: true, if: -> { status.in?(DECIDED_STATUSES) }
    validates :deduction_minutes,
              numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :deduction_minutes, presence: true, if: :deducted?

    before_save :stamp_reviewed_at, if: -> {
      will_save_change_to_status? && status.in?(DECIDED_STATUSES) && reviewed_at.nil?
    }

    def claim_active?
      claimed_by_id.present? && claimed_at.present? && claimed_at > CLAIM_TTL.ago
    end

    def claimed_by?(user)
      claim_active? && claimed_by_id == user.id
    end

    def flag?(bit) = flags.to_i & bit == bit

    def unknown_file? = flag?(FLAG_UNKNOWN_FILE)
    def cursor_strange? = flag?(FLAG_CURSOR_STRANGE)
    def neuralnet? = flag?(FLAG_NEURALNET)
    def no_hackatime_user? = flag?(FLAG_NO_HACKATIME_USER)
    def check_failed? = flag?(FLAG_CHECK_FAILED)

    def flag_names
      FLAGS_BY_BIT.filter_map { |bit, name| name if flag?(bit) }
    end

    private

    def stamp_reviewed_at
      self.reviewed_at = Time.current
    end
  end
end
