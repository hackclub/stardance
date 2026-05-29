class Votes::SkipsController < ApplicationController
  def create
    authorize Vote

    assignment = current_user.vote_assignments.assigned.find(params.require(:vote_assignment_id))
    assignment.skip

    redirect_to new_rate_path, notice: "Skipped."
  end
end
