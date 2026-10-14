# Holds one person for one reviewer while they work through everything waiting
# on them. The per-item claims (Certification::Integrity) stop two reviewers
# deciding the same check; this stops them working the same person at all.
# == Schema Information
#
# Table name: fraud_subject_claims
#
#  id          :bigint           not null, primary key
#  claimed_at  :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  reviewer_id :bigint           not null
#  subject_id  :bigint           not null
#
# Indexes
#
#  index_fraud_subject_claims_on_reviewer_id  (reviewer_id)
#  index_fraud_subject_claims_on_subject_id   (subject_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (subject_id => users.id)
#
class FraudSubjectClaim < ApplicationRecord
  CLAIM_TTL = 1.hour

  belongs_to :subject, class_name: "User"
  belongs_to :reviewer, class_name: "User"

  scope :active, -> { where(claimed_at: CLAIM_TTL.ago..) }

  # Takes the person for this reviewer, or returns nil when someone else still
  # holds them. One upsert on the unique index, so two reviewers arriving
  # together cannot both win.
  def self.claim(subject, reviewer)
    now = Time.current

    find_by_sql([ <<~SQL.squish, subject_id: subject.id, reviewer_id: reviewer.id, now: now, expired: CLAIM_TTL.ago ]).first
      INSERT INTO fraud_subject_claims (subject_id, reviewer_id, claimed_at, created_at, updated_at)
      VALUES (:subject_id, :reviewer_id, :now, :now, :now)
      ON CONFLICT (subject_id) DO UPDATE
        SET reviewer_id = EXCLUDED.reviewer_id, claimed_at = EXCLUDED.claimed_at, updated_at = EXCLUDED.updated_at
        WHERE fraud_subject_claims.claimed_at < :expired OR fraud_subject_claims.reviewer_id = :reviewer_id
      RETURNING *
    SQL
  end

  def self.held_by_other?(subject, reviewer)
    holder = active.find_by(subject_id: subject.id)
    holder.present? && holder.reviewer_id != reviewer.id
  end

  def self.release(subject, reviewer)
    where(subject_id: subject.id, reviewer_id: reviewer.id).delete_all
  end

  def active? = claimed_at > CLAIM_TTL.ago
  def expires_at = claimed_at + CLAIM_TTL
end
