module Stats
  class ShipFunnelController < ApplicationController
    def show
      authorize :ship_funnel

      @funnel = policy(:ship_funnel).refresh? ? ShipFunnel.fetch : ShipFunnel.cached
      ShipFunnelRefreshJob.perform_later unless @funnel
    end

    # Polled by the live view: the first three columns, plus any ships posted after `after`.
    def live
      authorize :ship_funnel

      ships = Post.where(postable_type: "Post::ShipEvent")
      render json: ShipFunnel.live.merge(last_ship_id: ships.maximum(:id) || 0, ships: ships_after(ships, params[:after]))
    end

    def refresh
      authorize :ship_funnel

      ShipFunnel.refresh
      redirect_to stats_ship_funnel_path, notice: "Jeremy Funnel recomputed."
    end

    private

    def ships_after(ships, after)
      return [] if after.blank?

      ships.where("posts.id > ?", after).includes(:user, :project, :postable).order(:id).last(20).map do |post|
        { id: post.id, user: post.user&.display_name, project: post.project.title, hours: post.postable.hours_at_ship }
      end
    end
  end
end
