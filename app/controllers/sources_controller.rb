class SourcesController < ApplicationController
  # Sets cookies[:referral_code] directly and redirects to / — avoids leaving
  # ?ref=<slug> in the URL since some ad blockers strip query params.
  def capture
    cookies[:referral_code] = {
      value: params[:src_slug],
      expires: 30.days.from_now,
      same_site: :lax
    }
    redirect_to root_path, status: :found
  end
end
