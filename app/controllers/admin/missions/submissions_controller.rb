module Admin
  module Missions
    class SubmissionsController < BaseController
      layout "application"

      skip_before_action :authorize_mission_management
      before_action :release_other_claims, only: [ :next, :claim ]
      before_action :set_submission, only: [ :show, :update, :claim, :undo ]
      # Hardware missions are reviewed on their own hardware dash (split
      # design/build), never the software submission queue.
      before_action :redirect_hardware_mission, only: [ :index, :next ]
      before_action :redirect_hardware_submission, only: [ :show, :update, :claim, :undo ]
      before_action :set_body_class

      def overview
        authorize Mission::Submission, :index?
        @missions = if global_reviewer?
          Mission.enabled.order(:name)
        else
          Mission.enabled.where(id: current_user.mission_memberships.select(:mission_id)).order(:name)
        end

        pending_counts = Mission::Submission
                           .where(status: "pending", deleted_at: nil)
                           .group(:mission_id)
                           .count

        oldest_pending = Mission::Submission
                           .where(status: "pending", deleted_at: nil)
                           .group(:mission_id)
                           .minimum(Arel.sql("COALESCE(pending_at, created_at)"))

        # Hardware missions are reviewed as funding requests + ship certs, not
        # submissions (which the build-review collapse auto-approves), so their
        # pending count comes from those queues instead.
        hardware_pending = hardware_pending_counts(@missions.select(&:hardware?))

        @mission_stats = @missions.map do |m|
          if m.hardware?
            { mission: m, pending: hardware_pending[m.id] || 0, oldest: nil }
          else
            { mission: m, pending: pending_counts[m.id] || 0, oldest: oldest_pending[m.id] }
          end
        end.sort_by { |s| -s[:pending] }
      end

      def index
        authorize Mission::Submission, :index?
        if @mission && !accessible_mission?(@mission)
          redirect_to admin_mission_reviews_path, alert: "You don't have access to review this mission."
          return
        end

        @stats = Mission::Submission.dashboard_stats(mission: @mission)
        @leaderboards = {
          daily: Mission::Submission.leaderboard(:daily, mission: @mission),
          weekly: Mission::Submission.leaderboard(:weekly, mission: @mission),
          alltime: Mission::Submission.leaderboard(:alltime, mission: @mission)
        }

        scope = policy_scope(Mission::Submission)
                  .includes(:reviewed_by, ship_event: { post: [ :user, :project ] })
                  .where.not(mission_id: Mission.where(hardware: true).select(:id))
        scope = scope.where(mission_id: @mission.id) if @mission

        scope = apply_filters(scope)
        @submissions = scope.order(Arel.sql("COALESCE(pending_at, created_at) ASC")).limit(100)
      end

      def show
        authorize @submission
        @reviewed_today = Mission::Submission.reviewed_today(current_user, mission: @mission)
        @project_review_history = Mission::Submission.review_history_for(
          @submission.ship_event&.post&.project, excluding: @submission
        )
        @versions = @submission.versions.order(created_at: :asc).to_a
        whodunnit_ids = @versions.map(&:whodunnit).compact.uniq
        @whodunnit_users = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
      end

      def update
        authorize @submission
        new_status = params.dig(:mission_submission, :status)
        feedback = params.dig(:mission_submission, :feedback).to_s.strip

        unless %w[approved rejected].include?(new_status)
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "Pick approve or reject." and return
        end

        unless @submission.reviewed_by_id == current_user.id
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "Claim this submission before reviewing." and return
        end

        if new_status == "rejected" && feedback.blank?
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "Provide a rejection reason." and return
        end

        can_transition = (new_status == "approved" && @submission.may_approve?) ||
                         (new_status == "rejected" && @submission.may_reject?)

        unless can_transition
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "This submission can't be #{new_status} right now." and return
        end

        detach_requested = new_status == "rejected" &&
                           ActiveModel::Type::Boolean.new.cast(params.dig(:mission_submission, :detach_project))
        detached = false

        Mission::Submission.transaction do
          if new_status == "approved"
            @submission.update!(reviewed_by: current_user, reviewed_at: Time.current, rejection_message: nil)
            @submission.approve!
            @submission.grant_rewards!(reviewer_id: current_user.id)
          else
            @submission.update!(reviewed_by: current_user, reviewed_at: Time.current, rejection_message: feedback)
            @submission.reject!
            detached = detach_submission_project! if detach_requested
          end
        end

        notify_builder(new_status)

        reviewed = Mission::Submission.reviewed_today(current_user, mission: @mission)
        verdict = detached ? "Rejected and detached the project" : new_status.titleize
        redirect_to next_admin_mission_submissions_path(mission_slug),
                    notice: "#{verdict}. That's #{reviewed} reviewed today."
      end

      def next
        authorize Mission::Submission, :index?
        if @mission && !accessible_mission?(@mission)
          redirect_to admin_mission_reviews_path, alert: "You don't have access to review this mission."
          return
        end
        skip_ids = parse_skip_ids

        # Hardware missions have their own dash, so the software "next" pool is
        # always software-only.
        missions_filter = if @mission
          @mission
        elsif global_reviewer?
          Mission.where(hardware: false).select(:id)
        else
          current_user.mission_memberships.joins(:mission)
                      .where(missions: { hardware: false }).select(:mission_id)
        end
        candidate = Mission::Submission.next_eligible(current_user, missions: missions_filter, skip_ids: skip_ids)
        unless candidate
          redirect_to admin_mission_submissions_path(mission_slug),
                      notice: "No more submissions to review." and return
        end

        claimed = Mission::Submission.atomic_claim!(candidate.id, current_user)
        if claimed
          redirect_to admin_mission_submission_path(mission_slug, claimed)
        else
          skip_ids << candidate.id
          redirect_to next_admin_mission_submissions_path(mission_slug, skip: skip_ids.join(","))
        end
      end

      def claim
        authorize @submission, :claim?
        claimed = Mission::Submission.atomic_claim!(@submission.id, current_user)
        if claimed
          redirect_to admin_mission_submission_path(mission_slug, claimed)
        else
          redirect_to admin_mission_submissions_path(mission_slug),
                      alert: "Could not claim this submission."
        end
      end

      def undo
        authorize @submission
        Mission::Submission.transaction do
          @submission.update!(reviewed_by: nil, reviewed_at: nil, rejection_message: nil)
          @submission.undo!
          @submission.reverse_rewards!(reviewer_id: current_user.id)
        end
        redirect_to admin_mission_submission_path(mission_slug, @submission),
                    notice: "Submission moved back to pending."
      end

      private

      def redirect_hardware_mission
        return unless @mission&.hardware?
        redirect_to design_admin_mission_hardware_reviews_path(@mission.slug)
      end

      def redirect_hardware_submission
        return unless @submission&.mission&.hardware?
        project = @submission.ship_event&.post&.project
        if project
          redirect_to admin_mission_hardware_review_path(@submission.mission.slug, project)
        else
          redirect_to admin_mission_reviews_path
        end
      end

      # Pending hardware review work (funding requests + ship certs) per mission,
      # keyed by mission id, for the review overview.
      def hardware_pending_counts(missions)
        return {} if missions.empty?

        project_to_mission = ::Project::MissionAttachment.active
                               .where(mission_id: missions.map(&:id))
                               .pluck(:project_id, :mission_id).to_h
        return {} if project_to_mission.empty?

        # Scoped the same way the mission's own hardware dash builds its queue,
        # so this badge cannot drift from the page it sends reviewers to. A
        # review on a soft-deleted or non-hardware project is unreachable from
        # every queue, so counting it reports a backlog nobody can work.
        counts = Hash.new(0)
        [ ::Certification::FundingRequest, ::Certification::Ship ].each do |model|
          model.in_hardware_mission_queue.pending
               .where(project_id: project_to_mission.keys)
               .pluck(:project_id).each do |pid|
            counts[project_to_mission[pid]] += 1
          end
        end
        counts
      end

      # Path segment for redirects: the mission's slug, or "all" for the
      # cross-mission queue.
      def mission_slug
        @mission&.slug || "all"
      end

      # Cross-mission views (overview, or slug "all") run with @mission nil.
      def set_mission
        slug = params[:mission_slug] || params[:slug]
        if slug.blank? || slug == "all"
          @mission = nil
        else
          @mission = Mission.with_deleted.find_by!(slug: slug)
        end
      end

      def accessible_mission?(mission)
        return true if global_reviewer?

        mission.memberships.exists?(user_id: current_user.id)
      end

      # Admins and global mission reviewers can review any mission; everyone
      # else (helpers included) is scoped to missions they're a member of.
      def global_reviewer?
        current_user.admin? || current_user.has_role?(:mission_reviewer)
      end

      def set_submission
        if @mission
          @submission = @mission.submissions.find(params[:id])
        else
          @submission = Mission::Submission.find(params[:id])
          @mission = @submission.mission
        end
      end

      def set_body_class
        @body_class = "app-layout-page"
      end

      def pundit_namespace(record)
        record
      end

      def release_other_claims
        Mission::Submission.release_all_for(current_user) if current_user
      end

      def parse_skip_ids
        params[:skip].to_s.split(",").map(&:to_i).reject(&:zero?)
      end

      def apply_filters(scope)
        status = params[:status]
        valid_states = Mission::Submission.aasm.states.map(&:name).map(&:to_s)
        if status.present? && valid_states.include?(status)
          scope = scope.where(status: status)
        elsif status != "all"
          scope = scope.where(status: "pending")
        end
        if params[:search].present?
          term = ActiveRecord::Base.sanitize_sql_like(params[:search].strip)
          scope = scope.joins(ship_event: { post: :project })
                       .where("projects.title ILIKE ?", "%#{term}%")
        end
        scope
      end


      # Detaches the submission's project from the mission it was rejected on,
      # but only while that mission is still the project's current one — so we
      # never yank a mission the builder has since swapped to. Returns whether
      # a detach actually happened. The MissionAttachment change is versioned
      # by PaperTrail (whodunnit set in the admin controller chain).
      def detach_submission_project!
        project = @submission.ship_event&.post&.project
        return false unless project
        return false unless project.current_mission == @submission.mission

        project.detach_mission!
        true
      end

      def notify_builder(status)
        builder = @submission.ship_event&.post&.user
        return unless builder

        klass = status == "approved" ? Notifications::Missions::SubmissionApproved : Notifications::Missions::SubmissionRejected
        klass.notify(recipient: builder, actor: current_user, record: @submission)
      rescue StandardError => e
        Rails.logger.warn("MissionSubmissions notify_builder: #{e.message}")
      end
    end
  end
end
