class MihiActivationsController < ApplicationController
  skip_before_action :remember_page
  before_action :set_paper_trail_whodunnit

  def create
    authorize MihiActivation
    MihiActivation.record!(user: current_user)
    head :no_content
  end
end
