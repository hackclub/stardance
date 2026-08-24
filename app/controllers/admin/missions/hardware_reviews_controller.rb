module Admin
  module Missions
    # A hardware mission's own two-stage review dash (design funding + build
    # certification), reviewed by that mission's team (per-mission reviewers,
    # global mission_reviewers, admins). Shares the queue machinery with the
    # global hardware dash via HardwareReviewQueue; only the covered projects,
    # authorization, and route helpers differ.
    class HardwareReviewsController < BaseController
      include HardwareReviewQueue

      skip_before_action :authorize_mission_management
      before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
      before_action :set_project, only: [ :show, :flag_for_fraud ]

      def index
        authorize_hardware_queue
        redirect_to design_admin_mission_hardware_reviews_path(@mission.slug)
      end

      private

      # The mission's own hardware projects (active attachment, hardware stage set).
      def reviewable_projects
        ::Project.where.not(hardware_stage: nil)
                 .where(id: ::Project::MissionAttachment.active.where(mission: @mission).select(:project_id))
      end

      def authorize_hardware_queue
        authorize @mission, :review?
      end

      def authorize_hardware_review(_project)
        authorize @mission, :review?
      end

      def hardware_review_path(project)
        admin_mission_hardware_review_path(@mission.slug, project)
      end

      def hardware_flag_for_fraud_path(project)
        flag_for_fraud_admin_mission_hardware_review_path(@mission.slug, project)
      end

      def hardware_queue_path(stage)
        if stage.to_s == "build"
          build_admin_mission_hardware_reviews_path(@mission.slug)
        else
          design_admin_mission_hardware_reviews_path(@mission.slug)
        end
      end

      def hardware_next_path(stage:, skip: nil)
        next_admin_mission_hardware_reviews_path(@mission.slug, stage: stage, skip: skip)
      end

      def hardware_queue_title(design)
        "#{@mission.name} #{design ? 'design' : 'build'} review queue"
      end

      def hardware_back_link
        { label: "← back to mission", path: admin_mission_reviews_path }
      end

      def set_project
        @project = ::Project.find(params[:project_id])
      end
    end
  end
end
