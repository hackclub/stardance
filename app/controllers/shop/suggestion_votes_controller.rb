class Shop::SuggestionVotesController < Shop::BaseController
  before_action -> { head :not_found unless Flipper.enabled?(:shop_suggestions, current_user) }
  before_action :require_login
  before_action :set_suggestion

  rescue_from ActiveRecord::RecordNotFound do
    redirect_to shop_suggestions_path, alert: "That suggestion no longer exists."
  end

  def create
    @vote = @suggestion.shop_suggestion_votes.build(user: current_user)
    authorize @vote, policy_class: ShopSuggestionVotePolicy

    if @vote.save
      redirect_to shop_suggestions_path, notice: "Vote cast! #{ShopSuggestionVote::VOTE_COST} Stardust spent."
    else
      redirect_to shop_suggestions_path, alert: @vote.errors.full_messages.to_sentence
    end
  end

  private

  def require_login
    redirect_to shop_suggestions_path, alert: "You must be logged in to vote." unless current_user
  end

  def set_suggestion
    @suggestion = ShopSuggestion.find(params[:suggestion_id])
  end
end
