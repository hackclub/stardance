class Shop::SuggestionsController < Shop::BaseController
  before_action -> { head :not_found unless Flipper.enabled?(:shop_suggestions, current_user) }

  def index
    authorize ShopSuggestion
    @new_suggestions = ShopSuggestion.kept.pending.includes(:user, :shop_suggestion_votes).order(created_at: :desc).limit(6)
    @suggestions = ShopSuggestion.kept.pending
      .left_joins(:shop_suggestion_votes)
      .select("shop_suggestions.*, COUNT(shop_suggestion_votes.id) AS vote_count")
      .includes(:user)
      .group("shop_suggestions.id").order(Arel.sql("vote_count DESC, shop_suggestions.id DESC"))
  end

  def history
    authorize ShopSuggestion
    @decided = ShopSuggestion.kept.where(aasm_state: [ :accepted, :rejected ]).includes(:user, :shop_suggestion_votes, :shop_item).order(updated_at: :desc)

    suggestion_ids = @decided.map { |s| s.id.to_s }
    deciding_versions = PaperTrail::Version
      .where(item_type: "ShopSuggestion", item_id: suggestion_ids)
      .where("object_changes -> 'aasm_state' ->> 1 IN (?)", [ "accepted", "rejected" ])
      .select(:item_id, :whodunnit)
    users_by_id = User.where(id: deciding_versions.filter_map(&:whodunnit).uniq).index_by { |u| u.id.to_s }
    @decided_by = deciding_versions.each_with_object({}) do |v, h|
      h[v.item_id.to_i] ||= users_by_id[v.whodunnit.to_s]
    end
  end

  def create
    authorize ShopSuggestion

    @suggestion = current_user.shop_suggestions.build(suggestion_params)

    if @suggestion.save
      redirect_to shop_suggestions_path, notice: "Your suggestion was submitted! #{ShopSuggestion::SUBMISSION_COST} Stardust has been deducted."
    else
      @new_suggestions = ShopSuggestion.kept.pending.includes(:user, :shop_suggestion_votes).order(created_at: :desc).limit(6)
      @suggestions = ShopSuggestion
        .kept
        .pending
        .includes(:user, :shop_suggestion_votes)
        .sort_by { |s| [ -s.vote_count, -s.id ] }
      render :index, status: :unprocessable_entity
    end
  end

  private

  def suggestion_params
    params.require(:shop_suggestion).permit(:name, :description, :url, :usd_cost, :image)
  end
end
