# frozen_string_literal: true

module Admin
  class FulfillmentPayoutsController < Admin::ApplicationController
    def index
      authorize FulfillmentPayoutRun
      @runs = FulfillmentPayoutRun.order(created_at: :desc).includes(:approved_by_user)
    end

    def show
      @run = FulfillmentPayoutRun.includes(lines: :user).find(params[:id])
      authorize @run
    end

    def approve
      @run = FulfillmentPayoutRun.find(params[:id])
      authorize @run

      if @run.may_approve?
        @run.approved_by_user = current_user
        @run.approved_at = Time.current
        @run.approve!

        ::PaperTrail::Version.create!(
          item_type: "FulfillmentPayoutRun",
          item_id: @run.id,
          event: "approved",
          whodunnit: current_user.id,
          object_changes: { aasm_state: %w[pending_approval approved] }.to_json
        )

        redirect_to admin_fulfillment_payout_path(@run), notice: "Payout run approved. #{@run.total_amount} tickets distributed to #{@run.lines.count} fulfillers."
      else
        redirect_to admin_fulfillment_payout_path(@run), alert: "Payout run cannot be approved from its current state."
      end
    end

    def reject
      @run = FulfillmentPayoutRun.find(params[:id])
      authorize @run

      if @run.may_reject?
        @run.reject!

        ::PaperTrail::Version.create!(
          item_type: "FulfillmentPayoutRun",
          item_id: @run.id,
          event: "rejected",
          whodunnit: current_user.id,
          object_changes: { aasm_state: %w[pending_approval rejected] }.to_json
        )

        redirect_to admin_fulfillment_payout_path(@run), notice: "Payout run rejected. Orders have been released for the next run."
      else
        redirect_to admin_fulfillment_payout_path(@run), alert: "Payout run cannot be rejected in its current state."
      end
    end

    def trigger
      authorize FulfillmentPayoutRun

      Shop::CalculateFulfillmentPayoutsJob.perform_later(manual: true)

      redirect_to admin_fulfillment_payouts_path, notice: "Manual payout calculation has been queued."
    end
  end
end
