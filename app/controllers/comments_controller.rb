class CommentsController < ApplicationController
  before_action :set_commentable
  before_action :set_comment, only: [ :destroy ]

  def create
    @comment = @commentable.comments.build(comment_params)
    @comment.user = current_user
    authorize @comment

    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: fallback_path }
      end
    else
      redirect_back fallback_location: fallback_path, alert: @comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @comment

    @comment.soft_delete!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: fallback_path }
    end
  end

  private

  def set_commentable
    if params[:devlog_id].present?
      @commentable = Post::Devlog.find(params[:devlog_id])
    else
      raise ActiveRecord::RecordNotFound, "Commentable not found"
    end
  end

  def set_comment
    @comment = @commentable.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:body)
  end

  def fallback_path
    post = Post.find_by(postable: @commentable)
    post ? project_devlog_path(post.project, @commentable) : root_path
  end
end
