class Mission::MigrateProjectsToHardwareJob < ApplicationJob
  queue_as :literally_whenever

  # When a mission is switched to hardware, its already-attached software
  # projects are converted to hardware so they match the mission's type. They
  # land in the "design" stage — the entry point of the hardware flow — leaving
  # already-hardware projects as-is.
  #
  # whodunnit threads the admin who flipped the toggle through to each project's
  # PaperTrail version so the bulk change stays attributable in the audit trail.
  def perform(mission_id, whodunnit = nil)
    mission = Mission.with_deleted.find_by(id: mission_id)
    return unless mission&.hardware?

    project_ids = mission.attachments.active.select(:project_id)

    PaperTrail.request(whodunnit: whodunnit) do
      Project.where(id: project_ids, hardware_stage: nil).find_each do |project|
        project.update!(hardware_stage: "design")
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[hardware-migration] mission=#{mission_id} project=#{project.id} skipped: #{e.message}")
      end
    end
  end
end
