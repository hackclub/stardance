# frozen_string_literal: true

class Admin::Certification::FundingRequests::ClaimsController < Admin::Certification::ApplicationController
  before_action :set_funding_request

  # POST /admin/certification/funding/:funding_request_id/claim
  def create
    authorize @funding_request, policy_class: Admin::Certification::FundingRequests::ClaimPolicy

    ::Certification::FundingRequest.release_all_for(current_user)
    claimed = ::Certification::FundingRequest.atomic_claim!(@funding_request.id, current_user)
    if claimed
      redirect_to admin_certification_funding_request_path(claimed)
    else
      redirect_to admin_certification_funding_requests_path, alert: "Couldn't claim that review, someone else got it"
    end
  end

  # DELETE /admin/certification/funding/:funding_request_id/claim
  def destroy
    authorize @funding_request, policy_class: Admin::Certification::FundingRequests::ClaimPolicy

    @funding_request.release_claim!
    redirect_to admin_certification_funding_requests_path, notice: "Unclaimed funding review for “#{@funding_request.project.title}.”"
  end

  private

  def set_funding_request
    @funding_request = ::Certification::FundingRequest.find(params[:funding_request_id])
  end
end
