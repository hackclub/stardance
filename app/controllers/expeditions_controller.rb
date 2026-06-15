class ExpeditionsController < ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:week_2_release, current_user) }
  before_action -> { @body_class = "app-layout-page" }

  def index
    @origin = viewer_origin
    expeditions = Expedition.upcoming.to_a
    attending = expeditions.select { |expedition| expedition.attending?(current_user&.slack_id) }
    @attending_ids = attending.map(&:id).to_set
    @featured = (attending.presence || expeditions).min_by { |expedition| featured_key(expedition) }
    @signed_up = @featured && @attending_ids.include?(@featured.id)
    @show_past = params[:past] == "1"
    @expanded = !@signed_up || @show_past || params[:expanded].present?
    browse = @show_past ? Expedition.chronological.to_a : expeditions
    @more = ordered_by_day(browse.reject { |e| e.id == @featured&.id || @attending_ids.include?(e.id) })
  end

  def show
    @expedition = Expedition.find_by_param!(params[:id])
    @origin = viewer_origin
    @signed_up = @expedition.attending?(current_user&.slack_id)
  end

  private

  def viewer_origin
    return nil unless current_user&.geocoded_lat && current_user&.geocoded_lon

    [ current_user.geocoded_lat, current_user.geocoded_lon ]
  end

  def featured_key(expedition)
    [
      @origin ? (expedition.distance_km_from(*@origin) || Float::INFINITY) : 0,
      expedition.date.nil? ? 1 : 0,
      expedition.date || Date.current,
      expedition.id
    ]
  end

  def ordered_by_day(expeditions)
    expeditions
      .group_by(&:date)
      .sort_by { |date, _group| [ date.nil? ? 1 : 0, date || Date.current ] }
      .flat_map { |_date, group| group.shuffle }
  end
end
