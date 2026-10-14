# == Schema Information
#
# Table name: certification_review_skips
#
#  id              :bigint           not null, primary key
#  reviewable_type :string           not null
#  skipped_at      :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  reviewable_id   :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_certification_review_skips_on_reviewable  (reviewable_type,reviewable_id)
#  index_certification_review_skips_on_user_id     (user_id)
#  index_review_skips_unique_reviewer_reviewable   (user_id,reviewable_type,reviewable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
module Certification
  # A reviewer's decision to pass on a submission for now. Persisted per
  # (reviewer, submission) so the hardware queue can keep a skipped submission
  # out of *that* reviewer's next-up for a cooldown window, while other
  # reviewers can still pick it up immediately. Re-skipping refreshes the clock.
  class ReviewSkip < ApplicationRecord
    self.table_name = "certification_review_skips"

    # How long a skip keeps a submission out of the skipper's queue.
    SKIP_COOLDOWN = 3.hours

    belongs_to :user
    belongs_to :reviewable, polymorphic: true

    # Skips still inside their cooldown window.
    scope :active, -> { where(skipped_at: SKIP_COOLDOWN.ago..) }

    # Records (or refreshes) this reviewer's skip of this submission. Kept to one
    # row per pair by the unique index, so re-skipping just restarts the clock.
    def self.record!(user:, reviewable:)
      skip = find_or_initialize_by(user: user, reviewable: reviewable)
      skip.skipped_at = Time.current
      skip.save!
      skip
    end
  end
end
