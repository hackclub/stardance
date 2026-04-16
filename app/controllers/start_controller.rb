# frozen_string_literal: true

class StartController < ApplicationController
  STEPS = %w[name project devlog signin].freeze

  before_action :redirect_signed_in_user
  before_action :set_step, only: :index
  before_action :enforce_step_order, only: :index

  def index
    authorize :start, :index?
    set_step

    # clr prefill if people go back
    if params[:clear_prefill] == "true" && @step == "project"
      session[:start_project_attrs] = nil
      session[:start_starter_project_name] = nil
    end

    if params[:email].present? && valid_email?(params[:email])
      session[:start_email] = params[:email].to_s.strip.downcase
      FunnelTrackerService.track(
        event_name: "start_flow_started",
        email: session[:start_email],
        properties: { source: "email_param" }
      )
    end

    @display_name = session[:start_display_name]
    @email = session[:start_email]
    @experience_level = session[:start_experience_level]
    @project_attrs = session[:start_project_attrs] || {}
    @starter_project_name = session[:start_starter_project_name]
    @devlog_body = session[:start_devlog_body]
    @devlog_attachment_ids = session[:start_devlog_attachment_ids] || []

    if @step == "project" && session[:start_project_attrs].blank?
      display_name = session[:start_display_name] || ""
      default_name = "First Project"
      title = display_name.present? ? "#{display_name}'s #{default_name}" : default_name
      description = "This is my first project on Stardance. I'm excited to share my progress!"

      @project_attrs = {
        "title" => title.strip.first(120),
        "description" => description.first(1_000)
      }
      session[:start_project_attrs] = @project_attrs
    end
  end

  def update_display_name
    display_name = params.fetch(:display_name, "").to_s.strip.first(50)
    email = params.fetch(:email, "").to_s.strip.downcase.first(255)

    unless valid_email?(email)
      redirect_to start_path(step: "name"), alert: "Please enter a valid email address."
      return
    end

    session[:start_display_name] = display_name
    session[:start_email] = email

    FunnelTrackerService.track(
      event_name: "start_flow_name",
      email: email
    )

    redirect_to start_path(step: "project")
  end

  # def update_experience
  #   experience_level = params.fetch(:experience_level, "").to_s.strip
  #
  #   unless %w[unseasoned seasoned].include?(experience_level)
  #     redirect_to start_path(step: "experience"), alert: "Please select your experience level."
  #     return
  #   end
  #
  #   session[:start_experience_level] = experience_level
  #   redirect_to start_path(step: "project")
  # end

  def prefill_project
    name = params.fetch(:name, "").to_s.strip
    description = params.fetch(:description, "").to_s.strip
    display_name = session[:start_display_name] || ""

    title = display_name.present? ? "#{display_name}'s #{name}" : name
    session[:start_project_attrs] = {
      title: title.strip.first(120),
      description: description.first(1_000)
    }
    session[:start_starter_project_name] = name
    redirect_to start_path(step: "project")
  end

  def update_project
    permitted = params.fetch(:project, {}).permit(:title, :description)
    session[:start_project_attrs] = {
      title: permitted[:title].to_s.strip.first(120),
      description: permitted[:description].to_s.strip.first(1_000)
    }

    FunnelTrackerService.track(
      event_name: "start_flow_project",
      email: session[:start_email]
    )

    redirect_to start_path(step: "devlog")
  end

  def update_devlog
    body = params.fetch(:devlog_body, "").to_s.strip.first(Post::Devlog::BODY_MAX_LENGTH)
    attachment_ids = Array(params[:devlog_attachment_ids]).compact_blank

    if attachment_ids.empty?
      redirect_to start_path(step: "devlog"), alert: "Please upload at least one image or video."
      return
    end

    session[:start_devlog_body] = body
    session[:start_devlog_attachment_ids] = attachment_ids
    session[:start_flow] = true

    FunnelTrackerService.track(
      event_name: "start_flow_devlog",
      email: session[:start_email]
    )

    redirect_to start_path(step: "signin")
  end

  private

  def redirect_signed_in_user
    return if current_user.blank?

    redirect_to(current_user.setup_complete? ? projects_path : kitchen_path)
  end

  def set_step
    @step = STEPS.include?(params[:step]) ? params[:step] : "name"
  end

  def enforce_step_order
    required = first_incomplete_step
    return if @step == required || step_accessible?(@step)

    redirect_to start_path(step: required), alert: "Please complete the previous steps first."
  end

  def step_accessible?(step)
    step_index = STEPS.index(step) || 0
    required_index = STEPS.index(first_incomplete_step) || 0
    step_index <= required_index
  end

  def first_incomplete_step
    return "name"       unless name_complete?
    # return "experience" unless experience_complete?
    return "project"    unless project_complete?
    return "devlog"     unless devlog_complete?
    "signin"
  end

  def name_complete?
    session[:start_display_name].present? && session[:start_email].present?
  end

  # def experience_complete?
  #   session[:start_experience_level].present?
  # end

  def project_complete?
    session[:start_project_attrs].present? && session[:start_project_attrs].any?
  end

  def devlog_complete?
    session[:start_devlog_body].present? && session[:start_devlog_attachment_ids].present?
  end

  def valid_email?(email)
    email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
  end
end
