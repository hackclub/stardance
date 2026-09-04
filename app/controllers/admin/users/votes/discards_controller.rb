# Manual counterpart to Vote::AutoDiscardJob, for ratings the automated
# discarder passed on but a reviewer knows are bad.
class Admin::Users::Votes::DiscardsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    @vote = @user.votes.find(params[:vote_id])
    authorize [ :admin, @vote ], :discard?

    if params[:reason].blank?
      redirect_back_to_votes(alert: "A reason is required to discard a rating.")
    elsif @vote.discard_by!(reviewer: current_user, reason: params[:reason])
      redirect_back_to_votes(notice: "Discarded the rating on #{@vote.project&.title || 'a deleted project'}.")
    else
      redirect_back_to_votes(alert: "That rating was already discarded.")
    end
  end

  private

  def redirect_back_to_votes(flash_message)
    redirect_back(fallback_location: admin_user_votes_path(@user), **flash_message)
  end
end
