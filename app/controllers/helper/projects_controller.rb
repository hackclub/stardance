module Helper
  class ProjectsController < ApplicationController
    def index
      authorize :helper, :view_projects?
      @q = params[:query]
      @filter = params[:filter] || "active"

      p = case @filter
      when "deleted"
        Project.unscoped.deleted
      when "all"
        Project.unscoped.all
      else
        Project.all
      end

      if @q.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        p = p.where("title ILIKE ? OR description ILIKE ?", q, q)
      end

      @pagy, @projects = pagy(:offset, p.order(:id))
    end

    def show
      authorize :helper, :view_projects?
      @project = Project.unscoped.find(params[:id])
      @ship_events = @project.ship_events.includes(:votes).order(created_at: :desc)
    end

    def restore
      authorize :helper, :restore_projects?
      @project = Project.unscoped.find(params[:id])

      if @project.deleted?
        @project.restore!
        redirect_to helper_project_path(@project), notice: "Project restored successfully."
      else
        redirect_to helper_project_path(@project), alert: "Project is not deleted."
      end
    end
  end
end
