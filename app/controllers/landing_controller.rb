class LandingController < ApplicationController
  def index
    @hide_sidebar = true

    if current_user
      redirect_to kitchen_path
    else
      respond_to do |format|
        format.html { render :index }
      end
    end
  end

  def edu
    @hide_sidebar = true
  end
end
