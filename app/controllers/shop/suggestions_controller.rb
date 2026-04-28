class Shop::SuggestionsController < Shop::BaseController
  before_action :require_login

  def create
    if current_user.has_dismissed?("shop_suggestion_box") || !Flipper.enabled?(:shop_suggestion_box, current_user)
      redirect_to shop_items_path, alert: "Suggestion box is not available."
      return
    end

    @suggestion = current_user.shop_suggestions.build(suggestion_params)

    if @suggestion.save
      Airtable::ShopSuggestionSyncJob.perform_later(@suggestion.id)
      redirect_to shop_items_path, notice: "Thank you for your suggestion!"
    else
      redirect_to shop_items_path, alert: @suggestion.errors.full_messages.to_sentence
    end
  end

  private

  def suggestion_params
    params.require(:shop_suggestion).permit(:item, :explanation, :link)
  end
end
