class FollowsController < ApplicationController
  before_action :load_target

  def create
    authorize @target, :follow?

    follow = current_user.follows_as_follower.find_or_initialize_by(followed: @target)
    follow.save unless follow.persisted?

    respond_to do |format|
      format.html { redirect_to profile_path(@target.display_name) }
      format.json { render json: { following: true, follower_count: @target.followers.where(banned: false).count } }
    end
  end

  def destroy
    authorize @target, :follow?

    current_user.follows_as_follower.where(followed: @target).destroy_all

    respond_to do |format|
      format.html { redirect_to profile_path(@target.display_name) }
      format.json { render json: { following: false, follower_count: @target.followers.where(banned: false).count } }
    end
  end

  private

  def load_target
    @target = User.find(params[:user_id])
  end
end
