module MissionReviewable
  extend ActiveSupport::Concern

  CLAIM_TTL = 5.minutes

  # Queue health targets for the dashboard (matches the cert queue's bar).
  QUEUE_TARGET = 25
  SLA_DAYS = 3

  class_methods do
    # missions: a Mission, a collection of mission ids, or nil for no filter.
    def available_for(user, missions: nil)
      scope = where(status: "pending").where(
        "(reviewed_by_id IS NULL OR claim_expires_at IS NULL OR claim_expires_at < ?) OR reviewed_by_id = ?",
        Time.current, user.id
      )
      scope = scope.where(mission_id: missions) if missions
      scope
    end

    def atomic_claim!(record_id, user)
      now = Time.current
      expires = now + CLAIM_TTL
      updated = where(id: record_id, status: "pending")
        .where("reviewed_by_id IS NULL OR claim_expires_at IS NULL OR claim_expires_at < ? OR reviewed_by_id = ?", now, user.id)
        .update_all(reviewed_by_id: user.id, claimed_at: now, claim_expires_at: expires, updated_at: now)
      updated.zero? ? nil : find(record_id)
    end

    def release_all_for(user)
      where(reviewed_by_id: user.id, status: "pending")
        .update_all(reviewed_by_id: nil, claim_expires_at: nil, updated_at: Time.current)
    end

    def next_eligible(user, missions: nil, skip_ids: [])
      scope = available_for(user, missions: missions)
      scope = scope.where.not(id: skip_ids) if skip_ids.any?
      scope.order(
        Arel.sql(sanitize_sql_array([ "CASE WHEN reviewed_by_id = ? THEN 0 ELSE 1 END", user.id ])),
        Arel.sql("COALESCE(pending_at, created_at)")
      ).first
    end

    # Queue health snapshot for the review dashboard, mirroring
    # Certification::Ship.dashboard_stats. Decisions are stamped reviewed_at.
    def dashboard_stats(mission: nil, now: Time.current)
      scoped = mission ? where(mission_id: mission.id) : all
      today = now.beginning_of_day
      week = now.beginning_of_week
      approved_count = scoped.approved.count
      rejected_count = scoped.rejected.count
      decided_count = approved_count + rejected_count
      decided = scoped.where(status: %w[approved rejected])

      {
        pending: scoped.pending.count,
        approved: approved_count,
        rejected: rejected_count,
        decided: decided_count,
        approval_rate: decided_count.zero? ? nil : (approved_count * 100.0 / decided_count).round,
        decisions_today: decided.where(reviewed_at: today..).count,
        new_today: scoped.where(created_at: today..).count,
        decisions_this_week: decided.where(reviewed_at: week..).count,
        new_this_week: scoped.where(created_at: week..).count,
        oldest_pending: scoped.pending.order(Arel.sql("COALESCE(pending_at, created_at)")).first,
        queue_target: QUEUE_TARGET,
        sla_days: SLA_DAYS,
        overdue_pending: scoped.pending.where("COALESCE(pending_at, created_at) < ?", now - SLA_DAYS.days).count
      }
    end

    # Reviewers ranked by decisions over a window: :daily, :weekly, :alltime.
    def leaderboard(period, mission: nil, now: Time.current, limit: 10)
      scope = where(status: %w[approved rejected]).where.not(reviewed_by_id: nil)
      scope = scope.where(mission_id: mission.id) if mission
      case period.to_sym
      when :daily  then scope = scope.where(reviewed_at: now.beginning_of_day..)
      when :weekly then scope = scope.where(reviewed_at: now.beginning_of_week..)
      end

      scope.joins(:reviewed_by)
           .group("users.display_name")
           .order(Arel.sql("COUNT(*) DESC"), Arel.sql("users.display_name ASC"))
           .limit(limit)
           .count
           .map { |name, count| { name: name, count: count } }
    end

    # Momentum counter for the review page — this reviewer's decisions today.
    def reviewed_today(user, mission: nil, now: Time.current)
      scope = where(reviewed_by_id: user.id, status: %w[approved rejected])
              .where(reviewed_at: now.beginning_of_day..)
      scope = scope.where(mission_id: mission.id) if mission
      scope.count
    end
  end

  def release_claim!
    return unless pending? && reviewed_by_id.present?
    update_columns(reviewed_by_id: nil, claim_expires_at: nil, updated_at: Time.current)
  end

  def claim_held_by?(user)
    reviewed_by_id == user.id && claim_expires_at.present? && claim_expires_at > Time.current
  end

  def claim_expired?
    claim_expires_at.nil? || claim_expires_at < Time.current
  end
end
