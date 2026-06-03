class MissionsController < ApplicationController
  before_action :set_body_class
  before_action :set_mission, only: [ :show, :guide ]
  before_action -> { @active_nav_slug = "missions" }

  def index
    authorize Mission

    buckets = Mission.visible_for(current_user).with_attached_icon
                     .order(featured_at: :desc, name: :asc)
                     .group_by(&:index_bucket)

    @available_missions = buckets[:available] || []
    @upcoming_missions  = (buckets[:upcoming] || []).sort_by(&:start_at).first(8)
    @ended_missions     = (buckets[:ended] || []).sort_by { |m| -m.end_at.to_f }.first(8)
    @draft_missions     = (buckets[:draft] || []).sort_by { |m| -m.updated_at.to_f }
  end

  def show
    authorize @mission
    @ordered_prizes       = @mission.prizes.ordered.includes(:shop_item).to_a
    @guide_outline        = @mission.guide_sections
    @stats                = mission_stats(@mission)
    @gallery_projects     = @mission.showcase_projects(limit: 3)
    @approved_project_ids = @mission.approved_submission_project_ids.to_set
    @estimated_label      = @mission.estimated_completion_label
    @active_project       = current_user&.active_project_for_mission(@mission)
    @progress_state       = compute_progress_state(@mission, @active_project, @guide_outline)
  end

  def guide
    authorize @mission
    @available_languages = @mission.available_languages
    @language            = @mission.resolve_storage_language(params[:language])
    @ordered_steps       = @mission.steps.where(deleted_at: nil).ordered.includes(:bodies).to_a
    @guide_outline       = @mission.guide_sections
    @active_project      = current_user&.active_project_for_mission(@mission)
    @completed_step_ids  = if @active_project
      @active_project.mission_section_completions
                     .where(mission_id: @mission.id)
                     .pluck(:mission_step_id)
                     .to_set
    else
      Set.new
    end
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end

  def set_mission
    @mission = Mission.find_by!(slug: params[:slug])
  end

  def compute_progress_state(mission, project, _outline)
    return :not_started unless project

    ship = project.ship_events
                  .joins(:mission_submission)
                  .where(mission_submissions: { mission_id: mission.id, deleted_at: nil })
                  .order("post_ship_events.created_at DESC")
                  .first

    return :in_progress unless ship

    case ship.certification_status
    when "approved"
      ship.payout_basis_locked_at.present? ? :completed : :in_voting
    when "pending"
      :in_review
    else
      # rejected / unknown — back to in_progress so the builder can re-ship.
      :in_progress
    end
  end

  def mission_stats(mission)
    {
      reviewed_count:  mission.submissions.where.not(status: "awaiting_certification").count,
      approved_count:  mission.submissions.where(status: "approved").count,
      active_projects: mission.attachments.active.distinct.count(:project_id)
    }
  end
end
