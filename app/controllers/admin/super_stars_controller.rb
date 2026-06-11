class Admin::SuperStarsController < Admin::ApplicationController
  def show
    authorize :super_star_dashboard

    @pending_pagy, @pending_projects = pagy(
      :offset,
      ::Project.fire_nomination_pending.includes(:nominated_fire_by).order(nominated_fire_at: :asc),
      page_key: "pending_page", limit: 25
    )

    @stars_pagy, @super_star_projects = pagy(
      :offset,
      ::Project.fire.includes(:marked_fire_by).order(marked_fire_at: :desc),
      page_key: "stars_page", limit: 25
    )
  end
end
