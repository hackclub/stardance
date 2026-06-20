class VotesController < ApplicationController
  include VoteTrackable

  def new
    authorize Vote

    @vote_policy = policy(Vote)

    if current_user && @vote_policy.open?
      if !current_user.shipped_projects.exists?
        @vote_blocked_reason = "You rate others' projects, they rate yours, and everyone earns stardust. Median payout is about 10 stardust/hr. Ship a project to unlock 15 ratings."
        @vote_blocked_title = "Ship first to rate"
        return
      end

      if current_user.vote_balance >= 0 && !@vote_policy.has_voting_path_ship?
        @vote_blocked_reason = "Rating is only available for projects going through the voting payout path."
        return
      end

      if current_user.vote_balance >= 0
        @vote_blocked_reason = "You've finished rating for this ship! Once your payout is processed, you can ship again to unlock more ratings."
        return
      end

      load_assignment
      track_assignment_view if @assignment
    end

    @ratings_total = Post::ShipEvent::VOTE_COST_PER_SHIP
    remaining = current_user ? [ -current_user.vote_balance, 0 ].max : 0
    @ratings_given = @ratings_total - remaining
  end

  def create
    authorize Vote

    @assignment = current_user.vote_assignments.assigned.find(params.require(:vote_assignment_id))

    track_vote_event("vote_submit_attempted",
                     assignment: @assignment,
                     properties: submit_timing_properties(@assignment)
                       .merge(feedback_stats(vote_params[:reason])))

    @vote = @assignment.submit_vote(vote_params)

    if @vote.persisted?
      track_vote_event("vote_submitted",
                       assignment: @assignment,
                       vote: @vote,
                       properties: submit_timing_properties(@assignment)
                         .merge(score_properties(@vote))
                         .merge(feedback_stats(@vote.reason)))
      redirect_to new_rate_path, notice: "Rating submitted."
    else
      @ship_event = @assignment.ship_event
      @project = @ship_event.project
      @vote_policy = policy(Vote)
      load_timeline_posts
      render :new, status: :unprocessable_entity
    end
  end

  private
    def track_assignment_view
      @assignment.mark_viewed!
      track_vote_event("vote_assignment_viewed",
                       assignment: @assignment,
                       properties: {
                         view_count: @assignment.view_count,
                         assignment_age_seconds: (Time.current - @assignment.created_at).round,
                         timeline_post_count: @timeline_posts&.size || 0
                       })
    end

    def submit_timing_properties(assignment)
      now = Time.current
      {
        assignment_age_seconds: (now - assignment.created_at).round,
        seconds_since_first_view: assignment.first_viewed_at && (now - assignment.first_viewed_at).round,
        seconds_since_last_view: assignment.last_viewed_at && (now - assignment.last_viewed_at).round,
        view_count: assignment.view_count
      }.compact
    end

    def score_properties(vote)
      scores = Vote::SCORE_COLUMNS_BY_CATEGORY.transform_values { |column| vote.public_send(column) }
      present_scores = scores.values.compact
      {
        scores: scores,
        score_average: present_scores.any? ? (present_scores.sum.to_f / present_scores.size).round(2) : nil,
        all_same_score: present_scores.any? && present_scores.uniq.size == 1
      }.compact
    end

    def feedback_stats(reason)
      text = reason.to_s
      {
        feedback_char_count: text.length,
        feedback_word_count: text.split(/\s+/).reject(&:blank?).size
      }
    end

    def load_assignment
      return unless current_user

      @assignment = Vote::Assignment.assign_to(current_user, user_agent: request.user_agent)
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
        .includes(postable: { attachments_attachments: :blob })
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
