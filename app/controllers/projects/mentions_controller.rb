class Projects::MentionsController < ApplicationController
  before_action :set_project
  before_action :require_feature_flag

  def index
    authorize @project, :mentions?
    @mentions = @project.mentions.order(created_at: :desc, id: :desc)
  end

  def new
    @mention = @project.mentions.build
    authorize @mention
  end

  def create
    @mention = @project.mentions.build(mention_params)
    authorize @mention

    if @mention.save
      destination = policy(@project).mentions? ? project_mentions_path(@project) : project_path(@project)
      redirect_to destination, notice: "Mention submitted! A reviewer will verify it."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

    def set_project
      @project = Project.find(params[:project_id])
    end

    def mention_params
      params.require(:project_mention).permit(:url, :submitter_notes)
    end

    def require_feature_flag
      return if Flipper.enabled?(:virality_bonus, current_user)

      render :coming_soon, status: :ok
    end
end
