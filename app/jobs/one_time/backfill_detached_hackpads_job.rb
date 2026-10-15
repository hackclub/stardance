# frozen_string_literal: true

# Restores mission routing for pending reviews submitted under Hackpad before
# the project detached. Does not change reviews, grants, prizes, or old history.
# Projects that moved to another mission or submitted after leaving are skipped.
#
# Dry-run first and inspect the returned candidate IDs before applying:
#   OneTime::BackfillDetachedHackpadsJob.perform_now
#   OneTime::BackfillDetachedHackpadsJob.perform_now(dry_run: false, project_ids: [...])
class OneTime::BackfillDetachedHackpadsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(dry_run: true, project_ids: nil)
    mission = Mission.find_by!(slug: "hackpad")
    history = Project::MissionAttachment.where(mission: mission).where.not(detached_at: nil)
    projects = Project.hardware.where(id: Certification::FundingRequest.pending.select(:project_id))
      .or(Project.hardware.where(id: Certification::Ship.pending.select(:project_id)))
      .where(id: history.select(:project_id))
      .where.not(id: Project::MissionAttachment.active.select(:project_id))
    projects = projects.where(id: project_ids) unless project_ids.nil?

    result = { candidates: [], restored: [], skipped: [] }
    PaperTrail.request(whodunnit: self.class.name) do
      projects.find_each do |project|
        project.with_lock do
          # Recheck after locking: the builder or reviewer may have acted since
          # the candidate query. Never replace a newer mission choice.
          attachment = project.mission_attachments.with_deleted.order(attached_at: :desc, id: :desc).first
          unless project.hardware? && !project.deleted? && !project.current_mission_attachment &&
                 attachment&.mission_id == mission.id && !attachment.deleted? && attachment.detached_at
            result[:skipped] << { project_id: project.id, reason: "Mission or project changed" }
            next
          end

          submitted_during_attachment = [ project.certification_funding_requests, project.ship_reviews ].any? do |reviews|
            reviews.pending.where(created_at: attachment.attached_at...attachment.detached_at).exists?
          end
          unless submitted_during_attachment
            result[:skipped] << { project_id: project.id, reason: "No pending review submitted while attached to Hackpad" }
            next
          end

          restored = project.mission_attachments.build(mission: mission)
          restored.restoring_historical_mission = true
          unless restored.valid?
            result[:skipped] << { project_id: project.id, reason: restored.errors.full_messages.to_sentence }
            next
          end

          result[:candidates] << project.id
          unless dry_run
            restored.save!
            result[:restored] << project.id
          end
        end
      end
    end

    Rails.logger.info "[BackfillDetachedHackpads] #{dry_run ? 'DRY RUN' : 'APPLY'} #{result.inspect}"
    result
  end
end
