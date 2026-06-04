# frozen_string_literal: true

class Admin::Certification::Ships::ClaimsController < Admin::Certification::ApplicationController
  before_action :set_ship

  # POST /admin/certification/ship/:ship_id/claim
  def create
    authorize @ship, policy_class: Admin::Certification::Ships::ClaimPolicy

    ::Certification::Ship.release_all_for(current_user)
    claimed = ::Certification::Ship.atomic_claim!(@ship.id, current_user)
    if claimed
      redirect_to admin_certification_ship_path(claimed)
    else
      redirect_to admin_certification_ships_path, alert: "Couldn't claim that review, someone else got it"
    end
  end

  # DELETE /admin/certification/ship/:ship_id/claim
  def destroy
    authorize @ship, policy_class: Admin::Certification::Ships::ClaimPolicy

    @ship.release_claim!
    redirect_to admin_certification_ships_path, notice: "Unclaimed review for \u201c#{@ship.project.title}.\u201d"
  end

  private

  def set_ship
    @ship = ::Certification::Ship.find(params[:ship_id])
  end
end
