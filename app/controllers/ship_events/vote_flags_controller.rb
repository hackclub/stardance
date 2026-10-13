class ShipEvents::VoteFlagsController < ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def create
    ship_event = Post::ShipEvent.find(params[:ship_event_id])
    redirect_path = project_path(ship_event.project, anchor: "payout-review")
    flags = selected_flags

    if flags.empty?
      return redirect_to redirect_path, alert: "Select at least one rating to flag."
    end

    if flags.any? { |flag| !flag[:details].length.between?(Vote::FLAG_DETAILS_MIN_LENGTH, Vote::FLAG_DETAILS_MAX_LENGTH) }
      return redirect_to redirect_path, alert: "Each flagged rating needs a reason of #{Vote::FLAG_DETAILS_MIN_LENGTH} to #{Vote::FLAG_DETAILS_MAX_LENGTH} characters."
    end

    # All or nothing: if any selected rating can no longer be flagged, none are.
    flagged = Vote.transaction do
      flags.all? do |flag|
        vote = ship_event.votes.find(flag[:vote_id])
        authorize vote, :flag?
        vote.flag_for_review_by(current_user, details: flag[:details])
      end || raise(ActiveRecord::Rollback)
    end

    if flagged
      redirect_to redirect_path, notice: "Flagged #{flags.size} #{"rating".pluralize(flags.size)} for review."
    else
      redirect_to redirect_path, alert: "One of those ratings can no longer be flagged. Nothing was flagged."
    end
  end

  private
    def selected_flags
      params.fetch(:flags, {}).each_pair.filter_map do |vote_id, flag|
        next unless flag[:selected] == "1"

        { vote_id: vote_id, details: flag[:details].to_s.strip }
      end
    end
end
