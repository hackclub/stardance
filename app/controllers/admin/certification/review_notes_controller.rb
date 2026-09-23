# frozen_string_literal: true

# Reviewer-only internal notes about a hardware project, written for the next
# reviewer. Append-only and shared across the project's funding and ship
# reviews. PaperTrail whodunnit is set by Admin::ApplicationController, so every
# note is attributable in the audit log.
class Admin::Certification::ReviewNotesController < Admin::Certification::ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_project

  def create
    @note = @project.review_notes.new(review_note_params.merge(author: current_user))
    authorize @note, policy_class: Admin::Certification::ReviewNotePolicy

    if @note.save
      redirect_to return_path, notice: "Reviewer note added."
    else
      redirect_to return_path,
                  alert: @note.errors.full_messages.to_sentence.presence || "Couldn't add that note."
    end
  end

  private

  # A flag rather than a url, so the caller can't choose where we redirect.
  def return_path
    if params[:second_stage].present?
      admin_certification_second_stage_review_path(@project)
    else
      hardware_review_path_for(@project)
    end
  end

  def set_project
    @project = Project.find(params[:project_id])
  end

  def review_note_params
    params.require(:certification_review_note).permit(:body)
  end
end
