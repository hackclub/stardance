# == Schema Information
#
# Table name: certification_ship_reviews
#
#  id               :bigint           not null, primary key
#  claim_expires_at :datetime
#  claimed_at       :datetime
#  decided_at       :datetime
#  feedback         :text
#  internal_reason  :text
#  lock_version     :integer          default(0), not null
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  project_id       :bigint           not null
#  reviewer_id      :bigint
#
# Indexes
#
#  idx_on_status_claim_expires_at_c7a5e87a52        (status,claim_expires_at)
#  index_certification_ship_reviews_on_decided_at   (decided_at)
#  index_certification_ship_reviews_on_reviewer_id  (reviewer_id)
#  index_ship_reviews_unique_pending_project        (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#
module Certification
  class Ship < ApplicationRecord
    self.table_name = "certification_ship_reviews"

    include Certification::Reviewable

    belongs_to :project
    belongs_to :reviewer, class_name: "User", optional: true

    has_paper_trail

    enum :status, {
      pending: 0,
      approved: 1,
      returned: 2
    }, default: :pending

    validates :feedback, length: { maximum: 10_000 }, allow_blank: true
    validates :internal_reason, length: { maximum: 10_000 }, allow_blank: true

    scope :for_reviewer, ->(user) {
      joins(:project)
        .where(projects: { deleted_at: nil })
        .where.not(project_id: user.memberships.select(:project_id))
    }

    def self.available_for(user)
      super.merge(for_reviewer(user))
    end

    before_save :stamp_claimed_at, if: -> { will_save_change_to_reviewer_id? && reviewer_id.present? && claimed_at.nil? }
    before_save :stamp_decided_at, if: -> { will_save_change_to_status? && status_change&.last != "pending" && decided_at.nil? }
    after_save :apply_verdict_to_project!, if: :saved_change_to_status?
    after_save_commit :notify_owner!, if: -> { saved_change_to_status? && !pending? }

    private

    def stamp_claimed_at
      self.claimed_at = Time.current
    end

    def stamp_decided_at
      self.decided_at = Time.current
    end

    def apply_verdict_to_project!
      return if pending?
      project.with_lock do
        project.start_review! if project.may_start_review?
        case status.to_sym
        when :approved
          project.approve! if project.may_approve?
          project.last_ship_event&.update!(certification_status: "approved")
        when :returned
          project.return_for_changes! if project.may_return_for_changes?
        end
      end
    end

    def notify_owner!
      owner = project.memberships.owner.first&.user
      return unless owner&.slack_id.present?

      case status.to_sym
      when :approved
        owner.dm_user("Your project '#{project.title}' was approved. It's out for voting now.")
      when :returned
        msg = "Your project '#{project.title}' needs changes before it can ship."
        msg += "\n\n#{feedback}" if feedback.present?
        owner.dm_user(msg)
      end
    end
  end
end
