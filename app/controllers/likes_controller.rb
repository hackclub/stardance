class LikesController < ApplicationController
  before_action :set_likeable

  def create
    @like = @likeable.likes.build(user: current_user)
    authorize @like

    if @like.save
      @likeable.reload

      respond_to do |format|
        format.json { render json: { liked: true, likes_count: @likeable.likes_count } }
        format.turbo_stream
        format.html { redirect_back fallback_location: @likeable }
      end
    else
      @likeable.reload

      respond_to do |format|
        format.json { render json: { liked: false, likes_count: @likeable.likes_count }, status: :unprocessable_entity }
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
      format.json { render json: { liked: false, likes_count: @likeable.likes_count } }
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
end
