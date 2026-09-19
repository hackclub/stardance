module User::Moderation
  extend ActiveSupport::Concern

  def ban!(reason: nil)
    update!(banned: true, banned_at: Time.current, banned_reason: reason)
    reject_pending_orders!(reason: reason || "User banned")
    withdraw_pending_funding_requests!(reason: reason || "User banned")
    soft_delete_projects!
    # Runs last: the ban has to be persisted and the projects gone before the
    # rejections go out, so the Airtable sync reports the ban as the reason.
    Certification::YswsReviewRejector.reject_pending_for_user!(self)
  end

  # Closes any still-live funding request that would otherwise sit in the
  # reviewer queue after the ban and pay out to this user. Marked `withdrawn`
  # (a non-verdict close), so the request leaves the queue without notifying the
  # user, skewing reviewer stats, or advancing the soon-to-be soft-deleted
  # project. Covers requests this user submitted as well as requests on projects
  # they own (where the grant would be paid to them as owner). The update is
  # versioned by PaperTrail, attributed to the ban.
  def withdraw_pending_funding_requests!(reason: "User banned")
    owned_project_ids = memberships.owner.select(:project_id)
    scope = Certification::FundingRequest.where(status: %i[pending misfiled])
    request_ids = scope.where(user_id: id).or(scope.where(project_id: owned_project_ids)).pluck(:id)
    return if request_ids.empty?

    PaperTrail.request(whodunnit: "User#ban!") do
      Certification::FundingRequest.where(id: request_ids).find_each do |request|
        request.update!(status: :withdrawn, internal_reason: reason)
      end
    end

    Rails.logger.info "[User#ban!] user=#{id} withdrew #{request_ids.size} pending funding request(s)"
  end

  def soft_delete_projects!
    projects.find_each do |project|
      project.soft_delete!(force: true)
    end
  end

  def unban!
    update!(banned: false, banned_at: nil, banned_reason: nil)
  end
end
