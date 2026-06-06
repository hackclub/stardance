class Api::V1::Projects::PostsController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_project

  def index
    return unless (limit = api_limit)

    posts = Post.with(
      feed_entries: [
        Post.of_devlogs(join: true)
            .where(post_devlogs: { deleted_at: nil })
            .where(project_id: @project.id)
            .select("posts.*"),
        Post.of_ship_events(join: true)
            .where.not(post_ship_events: { certification_status: "rejected" })
            .where(project_id: @project.id)
            .select("posts.*")
      ]
    )
    .from("feed_entries AS posts")
    .order(created_at: :desc)
    .includes(:postable)

    @pagy, @posts = pagy(posts, limit: limit)

    devlog_postables = @posts.select { |p| p.postable_type == "Post::Devlog" }.map(&:postable).compact
    if devlog_postables.any?
      ActiveRecord::Associations::Preloader.new(
        records: devlog_postables,
        associations: { attachments_attachments: :blob }
      ).call
    end
    preload_liked_devlog_ids(devlog_postables)
  end

  def show
    @post = find_post
    preload_liked_devlog_ids([@post.postable].compact) if @post.postable_type == "Post::Devlog"
  end

  def create
    unless @project.memberships.exists?(user: current_api_user)
      return render json: { error: "You don't have permission to post to this project", request_id: request.request_id }, status: :forbidden
    end

    if @project.hackatime_keys.blank?
      return render json: { error: "You must link at least one Hackatime project before posting", request_id: request.request_id }, status: :unprocessable_entity
    end

    devlog = current_api_user.with_advisory_lock("devlog_create", timeout_seconds: 10) do
      DevlogCreator.call(
        project: @project,
        user: current_api_user,
        body: params[:body],
        attachments: params[:attachments]
      )
    end

    if devlog&.persisted?
      @post = devlog.post
      preload_liked_devlog_ids([devlog])
      render :show, status: :created
    else
      errors = devlog ? devlog.errors.full_messages : [ "Could not create post ://" ]
      render json: { errors: errors, request_id: request.request_id }, status: :unprocessable_entity
    end
  end

  def update
    @post = find_post

    unless @post.postable_type == "Post::Devlog"
      return render json: { error: "Only devlog posts can be edited", request_id: request.request_id }, status: :forbidden
    end

    unless @post.user_id == current_api_user.id
      return render json: { error: "You don't have permission to edit this post", request_id: request.request_id }, status: :forbidden
    end

    @post.postable.update!(post_params)
    preload_liked_devlog_ids([@post.postable])
    render :show
  end

  def destroy
    @post = find_post

    unless @post.postable_type == "Post::Devlog"
      return render json: { error: "Only devlog posts can be deleted", request_id: request.request_id }, status: :forbidden
    end

    unless @post.user_id == current_api_user.id
      return render json: { error: "You don't have permission to delete this post", request_id: request.request_id }, status: :forbidden
    end

    if @project.shipped?
      return render json: { error: "Cannot delete a devlog from a shipped project", request_id: request.request_id }, status: :unprocessable_entity
    end

    @post.postable.soft_delete!
    head :no_content
  end

  private

  def set_project
    @project = Project.find_by!(id: params[:project_id], deleted_at: nil)
  end

  def find_post
    @project.posts
            .where(postable_type: [ "Post::Devlog", "Post::ShipEvent" ])
            .find(params[:id])
  end

  def post_params
    params.permit(:body)
  end
end
