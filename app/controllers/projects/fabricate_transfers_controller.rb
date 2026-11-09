# Moves a design-stage hardware project to Fabricate from the confirmation
# popup behind the "Move to Fabricate" button on the project page, then sends
# the owner over to finish the import there.
class Projects::FabricateTransfersController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :transfer_to_fabricate?

    # Under the project lock so a funding request can't slip in alongside it.
    transfer = @project.with_lock do
      @project.create_fabricate_transfer!(user: current_user) if @project.transferable_to_fabricate?
    end
    return redirect_to project_path(@project), alert: "This project can't move to Fabricate right now." unless transfer

    track_event "fabricate_transfer", { project_id: @project.id }
    redirect_to transfer.fabricate_url, allow_other_host: true
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
