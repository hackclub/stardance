module User::Moderation
  extend ActiveSupport::Concern

  def ban!(reason: nil)
    update!(banned: true, banned_at: Time.current, banned_reason: reason)
    reject_pending_orders!(reason: reason || "User banned")
    soft_delete_projects!
    resync_ysws_reviews_to_airtable!
    # Runs last: the ban has to be persisted and the projects gone before the
    # rejections go out, so the Airtable sync reports the ban as the reason.
    Certification::YswsReviewRejector.reject_pending_for_user!(self)
  end

  def soft_delete_projects!
    projects.find_each do |project|
      project.soft_delete!(force: true)
    end
  end

  def unban!
    update!(banned: false, banned_at: nil, banned_reason: nil)
    resync_ysws_reviews_to_airtable!
  end

  def resync_ysws_reviews_to_airtable!
    Certification::Ysws.rewritable_in_airtable.where(user_id: id).find_each do |review|
      Certification::YswsAirtableSyncJob.perform_later(review.id)
    end
  end
end
