class EventsController < ApplicationController
  discover_rail_widgets :upcoming_events

  before_action :set_body_class

  # Surfaces enabled missions to everyone, plus any draft missions the current
  # user can manage so owners/admins see their in-progress work alongside.
  def index
    manageable_ids = manageable_mission_ids
    base = Mission.includes(:icon_attachment)

    @missions = if current_user&.admin?
                  base.order(featured_at: :desc, name: :asc)
    elsif manageable_ids.any?
                  # Qualify `missions.id` — the icon_attachment JOIN brings in
                  # active_storage_attachments.id and makes a bare `id` ambiguous.
                  base.where("missions.enabled = TRUE OR missions.id IN (?)", manageable_ids)
                      .order(featured_at: :desc, name: :asc)
    else
                  base.where(enabled: true).order(featured_at: :desc, name: :asc)
    end

    @manageable_mission_ids = if current_user&.admin?
                                Set.new(@missions.map(&:id))
    else
                                Set.new(manageable_ids)
    end
  end

  private

  def manageable_mission_ids
    return [] unless current_user
    Mission::Membership.where(user_id: current_user.id, role: :owner)
                       .pluck(:mission_id)
  end

  def set_body_class
    @body_class = "app-layout-page"
  end
end
