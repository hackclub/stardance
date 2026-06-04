# frozen_string_literal: true

class Admin::Certification::PayoutsController < Admin::Certification::ApplicationController
  before_action :set_body_class
  before_action :set_payout_request, only: [ :show, :pay, :reject ]

  def index
    authorize ReviewerPayoutRequest

    @status = params[:status].presence_in(%w[pending paid rejected all]) || "all"
    scope = ReviewerPayoutRequest.includes(:user, :admin).order(created_at: :desc)
    scope = scope.where(aasm_state: @status) unless @status == "all"
    @payout_requests = scope
  end

  def show
    authorize @payout_request
  end

  def pay
    authorize @payout_request

    unless @payout_request.may_pay?
      redirect_to admin_certification_payout_path(@payout_request),
        alert: "This request cannot be paid in its current state."
      return
    end

    unless @payout_request.pay_out(
      admin: current_user,
      adjusted_amount: params[:adjusted_amount].presence,
      adjust_reason: params[:adjust_reason].presence
    )
      redirect_to admin_certification_payout_path(@payout_request),
        alert: @payout_request.errors.full_messages.to_sentence
      return
    end

    redirect_to admin_certification_payouts_path,
      notice: "Paid #{@payout_request.paid_amount} ✦ to #{@payout_request.user.display_name}."
  end

  def reject
    authorize @payout_request

    unless @payout_request.may_reject?
      redirect_to admin_certification_payout_path(@payout_request),
        alert: "This request cannot be rejected in its current state."
      return
    end

    unless @payout_request.reject_with_reason(admin: current_user, reason: params[:reject_reason].presence)
      redirect_to admin_certification_payout_path(@payout_request),
        alert: @payout_request.errors.full_messages.to_sentence
      return
    end

    redirect_to admin_certification_payouts_path,
      notice: "Payout request from #{@payout_request.user.display_name} rejected."
  end

  private

  def set_payout_request
    @payout_request = ReviewerPayoutRequest.find(params[:id])
  end

  def set_body_class
    @body_class = "app-layout-page"
  end
end
