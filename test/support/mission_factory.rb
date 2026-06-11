module MissionFactory
  def create_mission(prerequisite: nil)
    mission = Mission.create!(slug: "mission-#{SecureRandom.hex(4)}",
                              name: "Mission #{SecureRandom.hex(2)}",
                              description: "A test mission")
    mission.prerequisite_links.create!(prerequisite_mission: prerequisite) if prerequisite
    mission
  end

  def ship_to_mission!(project, user, mission, status: nil)
    ship_event = Post::ShipEvent.create!(body: "Shipped!", uploading_attachments: true)
    project.posts.create!(user: user, postable: ship_event)
    project.update!(shipped_at: Time.current)
    submission = Mission::Submission.create!(ship_event: ship_event, mission: mission, payout_path: "voting")
    submission.update_column(:status, status) if status
    submission
  end
end
