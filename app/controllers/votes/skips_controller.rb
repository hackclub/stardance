class Votes::SkipsController < ApplicationController
  include VoteTrackable

  def create
    authorize Vote

    assignment = current_user.vote_assignments.assigned.find(params.require(:vote_assignment_id))
    assignment.skip

    track_vote_event("vote_skipped",
                     assignment: assignment,
                     properties: {
                       assignment_age_seconds: (Time.current - assignment.created_at).round,
                       view_count: assignment.view_count
                     })

    redirect_to new_rate_path, notice: "Skipped."
  end
end
