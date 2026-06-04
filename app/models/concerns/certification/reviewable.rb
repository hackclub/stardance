module Certification
  module Reviewable
    extend ActiveSupport::Concern

    CLAIM_TTL = 30.minutes

    class_methods do
      def available_for(user)
        where(status: statuses[:pending]).where(
          "(reviewer_id IS NULL OR claim_expires_at IS NULL OR claim_expires_at < ?) OR reviewer_id = ?",
          Time.current, user.id
        )
      end

      def atomic_claim!(record_id, user)
        now = Time.current
        expires = now + CLAIM_TTL
        updated = where(id: record_id, status: statuses[:pending])
          .where("reviewer_id IS NULL OR claim_expires_at IS NULL OR claim_expires_at < ? OR reviewer_id = ?", now, user.id)
          .update_all(reviewer_id: user.id, claimed_at: now, claim_expires_at: expires, updated_at: now)
        updated.zero? ? nil : find(record_id)
      end

      def release_all_for(user)
        where(reviewer_id: user.id, status: statuses[:pending])
          .update_all(reviewer_id: nil, claim_expires_at: nil, updated_at: Time.current)
      end

      def next_eligible(user, skip_ids: [])
        scope = available_for(user)
        scope = scope.where.not(id: skip_ids) if skip_ids.any?
        scope.order(
          Arel.sql(sanitize_sql_array([ "CASE WHEN reviewer_id = ? THEN 0 ELSE 1 END", user.id ])),
          :created_at
        ).first
      end
    end

    def release_claim!
      return unless pending? && reviewer_id.present?

      self.class
        .where(id: id, status: self.class.statuses[:pending])
        .update_all(reviewer_id: nil, claim_expires_at: nil, updated_at: Time.current)
    end

    def claim_held_by?(user)
      reviewer_id == user.id && claim_expires_at.present? && claim_expires_at > Time.current
    end

    def claim_expired?
      claim_expires_at.nil? || claim_expires_at < Time.current
    end
  end
end
