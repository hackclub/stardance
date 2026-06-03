module User::ShopTutorial
  extend ActiveSupport::Concern

  def shop_tutorial_completed? = shop_tutorial_completed_at.present?

  def shop_tutorial_in_progress?
    shop_tutorial_started_at.present? && !shop_tutorial_completed?
  end

  def shop_tutorial_needed?
    hca_linked? && projects.exists? && !shop_tutorial_completed?
  end

  def shop_tutorial_notify?
    shop_tutorial_needed? && hackatime_identity.present? && identity_submitted? &&
      Post.where(user: self, postable_type: "Post::Devlog").exists?
  end

  def shop_tutorial_can_complete? = identity_submitted?

  def mark_shop_tutorial_started!
    return if shop_tutorial_started_at.present?

    update_columns(shop_tutorial_started_at: Time.current, updated_at: Time.current)
  end

  def mark_shop_tutorial_completed!
    return if shop_tutorial_completed?

    now = Time.current
    update_columns(
      shop_tutorial_started_at: shop_tutorial_started_at || now,
      shop_tutorial_completed_at: now,
      updated_at: now
    )
  end
end
