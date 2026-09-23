module BukuX3
  class RevealsController < ApplicationController
    skip_before_action :remember_page

    def show
      response.headers["Cache-Control"] = "no-store"
      if params[:preview].in?(%w[buku bean])
        authorize Event, :preview?
        render BukuX3RevealComponent.new(user: nil, preview: true, preview_role: params[:preview].to_sym), layout: false
      else
        authorize Event, :reveal?
        render BukuX3RevealComponent.new(user: current_user), layout: false
      end
    end
  end
end
