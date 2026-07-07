class Admin::VoteFlagsController < Admin::ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def index
    authorize Vote::Event

    @status = params[:status].presence_in(%w[pending reviewed]) || "pending"

    @pending_count = Vote::Event.pending_vote_flags.count
    @accepted_count = Vote::Event.accepted_vote_flags.count
    @rejected_count = Vote::Event.of_type("vote_flag_rejected").count

    scope =
      if @status == "reviewed"
        Vote::Event.reviewed_vote_flags.order(created_at: :desc)
      else
        Vote::Event.pending_vote_flags.order(created_at: :asc)
      end

    @pagy, @flags = pagy(scope.includes(:user, vote: [ :user, :project, :ship_event ]))

    @resolutions =
      if @status == "reviewed"
        Vote::Event.resolved_vote_flags
          .where(vote_id: @flags.map(&:vote_id))
          .includes(:user)
          .index_by(&:vote_id)
      else
        {}
      end
  end
end
