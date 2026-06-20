class Votes::AssignmentsController < ApplicationController
  include VoteTrackable

  before_action :load_assignment

  def demo
    open_external(:demo_url, "vote_demo_opened")
  end

  def repo
    open_external(:repo_url, "vote_repo_opened")
  end

  private
    def load_assignment
      authorize Vote, :create?
      @assignment = current_user.vote_assignments.assigned.find(params[:id])
    end

    def open_external(url_attribute, event_type)
      url = @assignment.ship_event.project&.public_send(url_attribute)

      if url.present?
        track_vote_event(event_type,
                         assignment: @assignment,
                         properties: {
                           assignment_status: @assignment.status,
                           assignment_age_seconds: (Time.current - @assignment.created_at).round
                         })
        redirect_to url, allow_other_host: true
      else
        redirect_to new_rate_path, alert: "That link isn't available."
      end
    end
end
