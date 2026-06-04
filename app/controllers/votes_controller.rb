class VotesController < ApplicationController
  before_action :set_voting_state

  def new
    authorize Vote

    if @voting_open && current_user && @has_shipped
      load_assignment
    end
  end

  def create
    authorize Vote

    @assignment = current_user.vote_assignments.assigned.find(params.require(:vote_assignment_id))
    @vote = @assignment.submit_vote(vote_params)

    if @vote.persisted?
      redirect_to new_rate_path, notice: "Vote submitted."
    else
      @ship_event = @assignment.ship_event
      @project = @ship_event.project
      load_timeline_posts
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_voting_state
      @has_shipped = current_user&.shipped_projects&.exists? || false
      @voting_open = Flipper.enabled?(:voting, current_user)
    end

    def load_assignment
      @assignment = Vote::Assignment.assign_to(current_user)
      if @assignment
        @ship_event = @assignment.ship_event
        @project = @ship_event.project
        return @assignment = nil unless @project

        @vote = Vote.new(ship_event: @ship_event, project: @project)
        load_timeline_posts
      end
    end

    def load_timeline_posts
      assigned_ship_post = @ship_event.post
      @timeline_posts = []
      return unless assigned_ship_post

      @timeline_posts = @project.posts
        .includes(postable: [ :attachments_attachments ])
        .where("posts.created_at <= ?", assigned_ship_post.created_at)
        .order(created_at: :desc)
        .select { |post| post.postable.present? }
        .reject { |post| post.postable_type == "Post::ShipEvent" && post.postable.certification_status == "rejected" }
    end

    def vote_params
      params.require(:vote).permit(
        :originality_score,
        :technical_score,
        :usability_score,
        :storytelling_score,
        :reason
      )
    end
end
