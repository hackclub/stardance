class HomeController < ApplicationController
  include OnboardingResumable
  discover_rail_widgets :raffle, :upcoming_events

  before_action :resume_or_expire_onboarding!, only: :index, if: -> { current_user.present? }

  def index
    authorize :home
    @body_class = "app-layout-page"
    @welcoming = params[:welcome] == "1" && current_user.present? && !current_user.has_dismissed?("home_intro")
    @body_class += " home-welcoming" if @welcoming

    load_composer if current_user.present?
  end

  private

  def load_composer
    @devlog = Post::Devlog.new
    @composer_projects = current_user.projects.order(updated_at: :desc)
    @selected_project = selected_composer_project
  end

  def selected_composer_project
    if params[:project_id].present?
      @composer_projects.find_by(id: params[:project_id]) || @composer_projects.first
    else
      @composer_projects.first
    end
  end
end
