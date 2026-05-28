# == Schema Information
#
# Table name: certification_devlog_reviews
#
#  id               :bigint           not null, primary key
#  approved_minutes :integer
#  justification    :text
#  original_minutes :integer
#  status           :string           default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  post_devlog_id   :bigint           not null
#  ysws_review_id   :bigint           not null
#
# Indexes
#
#  index_certification_devlog_reviews_on_post_devlog_id  (post_devlog_id)
#  index_certification_devlog_reviews_on_ysws_review_id  (ysws_review_id)
#
# Foreign Keys
#
#  fk_rails_...  (post_devlog_id => post_devlogs.id)
#  fk_rails_...  (ysws_review_id => certification_ysws_reviews.id)
#
module Certification
  class Devlog < ApplicationRecord
    self.table_name = "certification_devlog_reviews"

    belongs_to :post_devlog, class_name: "Post::Devlog"
    belongs_to :ysws_review, class_name: "Certification::Ysws"

    # Status enum for tracking review state
    enum :status, {
      pending: "pending",
      approved: "approved",
      rejected: "rejected"
    }, default: :pending

    # Validations
    validates :original_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false
    validates :approved_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # When approved, must have non-negative minutes
    validates :approved_minutes,
      presence: true,
      numericality: { greater_than_or_equal_to: 0 },
      if: :approved?

    # When rejected, approved_minutes must be 0 (not nil)
    validates :approved_minutes,
      presence: true,
      numericality: { equal_to: 0 },
      if: :rejected?

    # State transition methods
    def approve!(minutes, justification_text)
      raise "Approved minutes must be positive" if minutes.to_i <= 0
      raise "Justification required please!!!" if justification_text.blank?

      update!(
        status: "approved",
        approved_minutes: minutes,
        justification: justification_text
      )
    end

    def reject!(justification_text)
      raise "Justification required :pretty please:" if justification_text.blank?

      update!(
        status: "rejected",
        approved_minutes: 0,
        justification: justification_text
      )
    end

    def reset_to_pending!
      update!(
        status: "pending",
        approved_minutes: nil,
        justification: nil
      )
    end

    # Helper method to check if review has been completed
    def reviewed?
      approved? || rejected?
    end

    # Get display minutes (approved if reviewed, original if pending)
    def display_minutes
      reviewed? ? approved_minutes : original_minutes
    end
  end
end
