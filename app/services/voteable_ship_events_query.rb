class VoteableShipEventsQuery
  def self.call(user:, user_agent: nil)
    new(user:).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    Post::ShipEvent
      .joins(:project)
      .where(certification_status: "approved")
      .where.not(id: @user.votes.select(:ship_event_id))
      .where.not(projects: { id: @user.projects.select(:id) })
      .where.not(projects: { id: @user.project_skips.select(:project_id) })
  end
end
