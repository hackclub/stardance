class Admin::Projects::DevlogPhasesController < Admin::ApplicationController
  before_action :set_project

  def show
    redirect_to project_path(@project, reassign_devlogs: 1)
  end

  def update
    if params[:confirmation].present?
      data = verifier.verified(params[:confirmation])
      unless data && data["project_id"] == @project.id && data["actor_id"] == current_user.id
        raise Admin::DevlogPhaseChange::Error, "This preview expired or is invalid. Preview the changes again."
      end

      service = Admin::DevlogPhaseChange.new(@project, actor: current_user, phases: data.fetch("phases"), reason: data.fetch("reason"))
      result = service.apply!(fingerprint: data.fetch("fingerprint"))
      redirect_to project_path(@project), status: :see_other,
                  notice: "Updated #{result[:changes].size} devlog(s). Payout changes recorded in the audit log."
    else
      @phases = params.permit(phases: {}).fetch(:phases, {}).to_h
      @reason = params[:reason].to_s
      @preview = Admin::DevlogPhaseChange.new(@project, actor: current_user, phases: @phases, reason: @reason).preview
      @confirmation = verifier.generate(
        { "project_id" => @project.id, "actor_id" => current_user.id, "phases" => @phases,
          "reason" => @reason, "fingerprint" => @preview[:fingerprint] }, expires_in: 15.minutes
      )
      render :show, layout: false
    end
  rescue Admin::DevlogPhaseChange::Error, ActiveRecord::RecordInvalid => e
    if turbo_frame_request?
      @preview = nil
      @error = e.message
      render :show, layout: false, status: :unprocessable_entity
    else
      redirect_to project_path(@project, reassign_devlogs: 1, anchor: "devlog-phase-form"),
                  status: :see_other, alert: e.message
    end
  end

  private

  def set_project
    @project = ::Project.find(params[:project_id])
    authorize @project, :reassign_devlog_phases?
  end

  def verifier
    Rails.application.message_verifier("admin-devlog-phase-change")
  end
end
