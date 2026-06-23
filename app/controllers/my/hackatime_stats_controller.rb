class My::HackatimeStatsController < ApplicationController
  def show
    authorize :my, :show_hackatime_stats?

    seconds = Rails.cache.fetch("hackatime_stats_display:#{current_user.id}", expires_in: 5.minutes) do
      current_user.all_time_coding_seconds
    end

    render json: { seconds: seconds, formatted: helpers.format_seconds(seconds) }
  end
end
