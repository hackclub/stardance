module User::Achievements
  extend ActiveSupport::Concern

  def earned_achievement_slugs
    @earned_achievement_slugs ||= achievements.pluck(:achievement_slug).to_set
  end

  def recalculate_has_pending_achievements!
    update_column(:has_pending_achievements, pending_achievement_notifications.exists?)
  end

  def earned_achievement?(slug)
    earned_achievement_slugs.include?(slug.to_s)
  end

  def award_achievement!(slug, notified: false)
    return nil if earned_achievement?(slug)

    achievement = ::Achievement.find(slug)
    achievements.create!(achievement_slug: slug.to_s, earned_at: Time.current, notified: notified)
    @earned_achievement_slugs&.add(slug.to_s)
    update_column(:has_pending_achievements, true) unless notified
    achievement
  end

  def revoke_achievement!(slug)
    record = achievements.find_by(achievement_slug: slug.to_s)
    return nil unless record

    record.destroy!
    @earned_achievement_slugs&.delete(slug.to_s)
    recalculate_has_pending_achievements!
    true
  end
end
