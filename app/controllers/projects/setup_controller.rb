class Projects::SetupController < ApplicationController
  layout "onboarding"

  before_action :require_signed_in!
  before_action :load_setup_project_for_prefill, only: %i[name missions]
  before_action :load_setup_project, only: %i[link_account welcome]

  DEFAULT_PROJECT_TITLE = "Untitled project".freeze

  EXPERIENCE_TO_DIFFICULTIES = {
    "none"        => %w[beginner],
    "little"      => %w[beginner],
    "some"        => %w[beginner intermediate],
    "experienced" => %w[intermediate advanced]
  }.freeze

  def idea
    authorize :project_setup
  end

  def submit_idea
    authorize :project_setup

    case params[:idea].to_s
    when "yes"
      track_event "project_setup_started", { has_idea: true }
      redirect_to projects_setup_name_path
    when "no"
      track_event "project_setup_started", { has_idea: false }
      redirect_to projects_setup_missions_path
    else
      redirect_to projects_setup_path, alert: "Please pick one."
    end
  end

  def name
    authorize :project_setup
  end

  MAX_TITLE_LENGTH = 120
  MAX_DESCRIPTION_LENGTH = 1_000

  def submit_name
    authorize :project_setup

    title = params[:title].to_s.strip
    description = params[:description].to_s.strip

    if title.blank?
      redirect_to projects_setup_name_path, alert: "Give your project a name." and return
    end
    if title.length > MAX_TITLE_LENGTH
      redirect_to projects_setup_name_path, alert: "Keep the name under #{MAX_TITLE_LENGTH} characters." and return
    end
    if description.length > MAX_DESCRIPTION_LENGTH
      redirect_to projects_setup_name_path, alert: "Keep the description under #{MAX_DESCRIPTION_LENGTH} characters." and return
    end

    project = find_or_create_setup_project!
    project.update!(title: title, description: description.presence)
    track_event "project_created", { project_id: project.id, source: "setup" }
    redirect_to next_gate_after_details_path
  end

  def missions
    authorize :project_setup
    @missions = suggested_missions
  end

  def submit_mission
    authorize :project_setup

    project = find_or_create_setup_project!

    if params[:figure_it_out_later].present?
      redirect_to(next_gate_after_details_path) and return
    end

    slug = params[:mission_slug].to_s
    mission = Mission.available.find_by(slug: slug)
    unless mission
      redirect_to projects_setup_missions_path, alert: "That mission isn't available." and return
    end

    existing = project.mission_attachments.find_by(mission_id: mission.id)

    if existing&.detached_at.nil? && existing.present?
      redirect_to(next_gate_after_details_path) and return
    end

    is_first_attach = existing.nil?

    if existing
      existing.update!(detached_at: nil, attached_at: Time.current)
    else
      project.mission_attachments.create!(mission: mission, attached_at: Time.current)
    end

    # Authored defaults apply only on first attach — never overwrite a
    # builder's edits on re-attach.
    if is_first_attach
      attrs = {}
      if project.title.blank? || project.title == DEFAULT_PROJECT_TITLE
        attrs[:title] = mission.default_project_title.presence || mission.name
      end
      if project.description.blank? && mission.default_project_description.present?
        attrs[:description] = mission.default_project_description
      end
      project.update!(attrs) if attrs.any?
    end

    track_event "mission_attached", { project_id: project.id, mission_slug: slug }
    redirect_to next_gate_after_details_path
  end

  def link_account
    authorize :project_setup
    session[:return_to] = projects_setup_welcome_path
  end

  def welcome
    authorize :project_setup

    unless current_user.hca_linked?
      redirect_to projects_setup_link_account_path and return
    end

    session.delete(:setup_project_id)
    redirect_to project_path(@setup_project, welcome: 1)
  end

  private

  def require_signed_in!
    return if current_user.present?
    redirect_to root_path, alert: "Please sign in to start a project."
  end

  def load_setup_project
    @setup_project = find_setup_project
    return if @setup_project

    redirect_to projects_setup_path
  end

  # For GET steps that may be revisited before a project exists — render with
  # nil and let the view show empty fields.
  def load_setup_project_for_prefill
    @setup_project = find_setup_project
  end

  def find_setup_project
    project_id = session[:setup_project_id]
    if project_id.present?
      found = current_user.projects.where(id: project_id, ship_status: "draft").first
      return found if found
    end

    # Session lost (cleared cookies / different device): fall back to the
    # guest's most recent draft so they can resume the link gate.
    return nil unless current_user.guest?

    fallback = current_user.projects.where(ship_status: "draft").order(updated_at: :desc).first
    session[:setup_project_id] = fallback.id if fallback
    fallback
  end

  def find_or_create_setup_project!
    existing = find_setup_project
    return existing if existing

    project = Project.new(title: DEFAULT_PROJECT_TITLE)
    Project.transaction do
      project.save!
      project.memberships.create!(user: current_user, role: :owner)
    end
    session[:setup_project_id] = project.id
    project
  end

  def next_gate_after_details_path
    current_user.hca_linked? ? projects_setup_welcome_path : projects_setup_link_account_path
  end

  def suggested_missions
    scope = Mission.available
                   .where.not(id: missions_user_already_has_a_project_on)
                   .includes(:icon_attachment)

    difficulties = EXPERIENCE_TO_DIFFICULTIES[current_user.experience_level.to_s]
    if difficulties.present?
      matched = scope.where(difficulty: difficulties)
                     .order(featured_at: :desc)
                     .limit(6)
                     .to_a
      remaining_slots = 6 - matched.size
      if remaining_slots.positive?
        rest = scope.where.not(id: matched.map(&:id))
                    .order(featured_at: :desc)
                    .limit(remaining_slots)
        matched + rest.to_a
      else
        matched
      end
    else
      scope.order(featured_at: :desc).limit(6).to_a
    end
  end

  def missions_user_already_has_a_project_on
    current_user.projects
                .where(deleted_at: nil)
                .joins(:mission_attachments)
                .where(project_mission_attachments: { detached_at: nil, deleted_at: nil })
                .pluck("project_mission_attachments.mission_id")
                .uniq
  end
end
