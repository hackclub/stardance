# Moves a design-stage hardware project to Fabricate from the confirmation
# popup behind the "Move to Fabricate" button on the project page, then sends
# the owner over to it.
class Projects::FabricateTransfersController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :transfer_to_fabricate?

    # Under the project lock so a funding request can't slip in mid-transfer.
    transfer = @project.with_lock do
      next unless @project.transferable_to_fabricate?

      fabricate_project_id = FabricateService.import_project!(@project, owner: current_user, host: request.base_url)
      @project.create_fabricate_transfer!(user: current_user, fabricate_project_id: fabricate_project_id)
    end
    unless transfer
      return redirect_to project_path(@project), alert: "This project can't move to Fabricate right now."
    end

    track_event "fabricate_transfer", { project_id: @project.id, fabricate_project_id: transfer.fabricate_project_id }
    redirect_to transfer.fabricate_url, allow_other_host: true
  rescue FabricateService::Error => e
    Rails.error.report(e, context: { category: "fabricate_transfer", project_id: @project.id })
    redirect_to project_path(@project), alert: "We couldn't reach Fabricate, so your project hasn't moved. Try again in a minute."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
