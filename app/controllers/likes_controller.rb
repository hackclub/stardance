class LikesController < ApplicationController
  before_action :set_likeable

  def create
    @like = @likeable.likes.build(user: current_user)
    authorize @like

    if @like.save
      @likeable.reload

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: @likeable }
      end
    else
      @likeable.reload

      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { redirect_back fallback_location: @likeable, alert: @like.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @like = @likeable.likes.find_by!(user: current_user)
    authorize @like

    @like.destroy
    @likeable.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: @likeable }
    end
  end

  private

  def set_likeable
    if params[:devlog_id].present?
      @likeable = Post::Devlog.find(params[:devlog_id])
    else
      raise ActiveRecord::RecordNotFound, "Likeable not found"
    end
  end

  def set_liked_devlog_ids
    if current_user
      @liked_devlog_ids = Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: @likeable.id).pluck(:likeable_id).to_set
    else
      @liked_devlog_ids = Set.new
    end
  end
end
