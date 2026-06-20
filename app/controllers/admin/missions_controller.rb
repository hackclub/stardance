module Admin
  class MissionsController < Admin::ApplicationController
    # Override the default tan kitchen layout from Admin::ApplicationController.
    layout "application"

    before_action :set_body_class
    before_action :set_mission, only: [ :show, :edit, :update, :destroy, :restore ]

    def index
      authorize Mission

      scope = case params[:filter]
      when "active"
                Mission.where(enabled: true)
                       .where("start_at IS NULL OR start_at <= ?", Time.current)
                       .where("end_at IS NULL OR end_at > ?", Time.current)
      when "disabled"
                Mission.where(enabled: false)
      when "deleted"
                Mission.with_deleted.where.not(deleted_at: nil)
      else
                Mission.all
      end
      @missions = scope.order(created_at: :desc).limit(200)
      @current_filter = params[:filter]
      @submission_counts = Mission::Submission.where(mission_id: @missions.map(&:id)).group(:mission_id).count
    end

    def new
      @mission = Mission.new
      authorize @mission
    end

    # New missions are disabled drafts — everything beyond slug/name/description
    # is configured on the edit page after the redirect.
    def create
      @mission = Mission.new(create_params.merge(enabled: false))
      authorize @mission

      if @mission.save
        redirect_to edit_admin_mission_path(@mission.slug),
                    notice: "Draft mission created — configure it below, then flip Enabled when it's ready."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @mission
      @submissions = @mission.submissions.order(created_at: :desc).limit(50)

      mission_versions = ::PaperTrail::Version.where(item_type: "Mission", item_id: @mission.id.to_s)
      child_versions = child_audit_versions
      @versions = mission_versions.or(child_versions).order(created_at: :desc).limit(50)

      whodunnit_ids = @versions.pluck(:whodunnit).compact.uniq
      @whodunnit_users = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
    end

    def edit
      authorize @mission
      load_edit_locals
    end

    def update
      authorize @mission

      handle_prerequisite_changes

      if @mission.update(mission_params)
        redirect_to edit_admin_mission_path(@mission.slug), notice: "Mission updated."
      else
        load_edit_locals
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @mission
      @mission.update!(deleted_at: Time.current, enabled: false)
      redirect_to admin_missions_path, notice: "Mission soft-deleted."
    end

    def restore
      authorize @mission, :restore?
      @mission.update!(deleted_at: nil)
      redirect_to admin_mission_path(@mission.slug), notice: "Mission restored."
    end

    private

    def set_body_class
      @body_class = "app-layout-page"
    end

    def set_mission
      @mission = Mission.with_deleted.find_by!(slug: params[:slug])
    end

    def load_edit_locals
      @current_language    = @mission.resolve_storage_language(params[:language].presence)
      @available_languages = @mission.available_languages

      # body_for is .detect-based; preloading :bodies turns the per-step
      # body lookup into one SELECT + in-memory pick instead of N queries.
      @steps       = @mission.steps.where(deleted_at: nil).ordered.includes(:bodies)
      @prizes      = @mission.prizes.ordered.includes(:shop_item)
      @memberships = @mission.memberships.includes(:user).order(:role, :id)
      @unlocks     = @mission.shop_unlocks.includes(:shop_item)

      # Admin-only sections (slug / owner CRUD / danger zone) on the merged edit page.
      if policy(@mission).manage_owners?
        @owners = @mission.memberships
                          .where(role: Mission::Membership.roles[:owner])
                          .includes(:user)
                          .order(:created_at)
      end
    end

    # versions.item_id is a varchar — pair each id list with its item_type so
    # ids from a sibling child table can't leak in.
    def child_audit_versions
      scopes = {
        "Mission::GuideVariant" => @mission.guide_variants.pluck(:id),
        "Mission::Step" => @mission.steps.with_deleted.pluck(:id),
        "Mission::Prize" => @mission.prizes.with_deleted.pluck(:id),
        "Mission::Membership" => @mission.memberships.pluck(:id),
        "Mission::ShopUnlock" => @mission.shop_unlocks.pluck(:id)
      }.filter_map do |item_type, ids|
        next if ids.empty?
        ::PaperTrail::Version.where(item_type: item_type, item_id: ids.map(&:to_s))
      end

      scopes.reduce(::PaperTrail::Version.none) { |query, scope| query.or(scope) }
    end

    def handle_prerequisite_changes
      mission_input = params[:mission] || {}

      if (add_id = mission_input[:add_prerequisite_id].presence)
        @mission.prerequisite_links.find_or_create_by!(prerequisite_mission_id: add_id)
      end

      if (remove_id = mission_input[:remove_prerequisite_id].presence)
        @mission.prerequisite_links.where(prerequisite_mission_id: remove_id).destroy_all
      end
    end

    def create_params
      params.require(:mission).permit(:slug, :name, :description)
    end

    # :slug stays admin-only — public URL changes are admin-prerogative.
    def mission_params
      permitted = [
        :name, :description, :difficulty, :submission_guide,
        :enabled, :start_at, :end_at, :featured_at,
        :achievement_name, :achievement_description, :icon, :banner,
        :estimated_completion_minutes, :fixed_stardust_payout, :guide_url, :guide_sections_count,
        :default_project_title, :default_project_description
      ]
      permitted << :slug if policy(@mission).manage_owners?
      params.require(:mission).permit(*permitted)
    end
  end
end
