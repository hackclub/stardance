class Admin::Shop::SuggestionsController < Admin::ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:shop_suggestions, current_user) }
  before_action :set_suggestion, only: [ :accept, :reject, :delete ]

  def accept
    authorize @suggestion

    redirect_to new_admin_shop_item_path(
      suggestion_id: @suggestion.id,
      prefill_name: @suggestion.name,
      prefill_description: @suggestion.description,
      prefill_usd_cost: @suggestion.usd_cost
    )
  end

  def delete
    authorize @suggestion

    @suggestion.discard!

    redirect_to shop_suggestions_path, notice: "Suggestion removed."
  end

  def reject
    authorize @suggestion

    @suggestion.update!(rejection_reason: params[:rejection_reason])
    @suggestion.reject!

    SendSlackDmJob.perform_later(
      @suggestion.user.slack_id,
      "Your shop suggestion \"#{@suggestion.name}\" was not approved.#{" Reason: #{@suggestion.rejection_reason}" if @suggestion.rejection_reason.present?}"
    )

    redirect_to shop_suggestions_path, notice: "Suggestion rejected."
  end

  private

  def set_suggestion
    @suggestion = ShopSuggestion.find(params[:id])
  end
end
