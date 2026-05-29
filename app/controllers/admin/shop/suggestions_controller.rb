class Admin::Shop::SuggestionsController < Admin::ApplicationController
    before_action :set_suggestion, only: [ :dismiss, :disable_for_user ]

    def index
      authorize ShopSuggestion

      @pagy, @suggestions = pagy(
        ShopSuggestion.includes(:user).order(created_at: :desc)
      )
    end

    def dismiss
      authorize @suggestion, :destroy?

      @suggestion.destroy

      redirect_to admin_shop_suggestions_path, notice: "Suggestion dismissed."
    end

    def disable_for_user
      authorize @suggestion, :update?

      user = @suggestion.user

      user.dismiss_thing!("shop_suggestion_box")

      @suggestion.destroy

      redirect_to admin_shop_suggestions_path, notice: "Suggestion box disabled for #{user.display_name}."
    end

    private

    def set_suggestion
      @suggestion = ShopSuggestion.find(params[:id])
    end
end
