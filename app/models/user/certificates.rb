module User::Certificates
  extend ActiveSupport::Concern

  included do
    has_one :certificate, dependent: :destroy
  end

  def approved_hours
    approved_ship_hours + approved_funding_hours
  end

  def certificate_eligible?
    approved_hours >= Certificate::REQUIRED_APPROVED_HOURS
  end

  private

  def approved_ship_hours
    Post.approved_ship_events_by(self).sum("post_ship_events.hours_at_ship")
  end

  # The design and pre-funding time a hardware ship drops (see
  # Post::ShipEvent#devlogs_in_ship_window) was reviewed through the funding
  # request instead, so it counts once the request is approved.
  def approved_funding_hours
    funded_projects = Certification::FundingRequest.approved
      .where(user_id: id, project_id: Project.hardware.select(:id))
      .group(:project_id)
      .select("project_id, MIN(created_at) AS funded_at")

    Post.of_devlogs(join: true)
        .joins("INNER JOIN (#{funded_projects.to_sql}) funded_projects ON funded_projects.project_id = posts.project_id")
        .where(post_devlogs: { deleted_at: nil })
        .where("post_devlogs.phase = 'design' OR posts.created_at < funded_projects.funded_at")
        .sum("post_devlogs.duration_seconds").to_f / 3600
  end
end
