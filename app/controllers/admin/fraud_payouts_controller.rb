# frozen_string_literal: true

module Admin
  class FraudPayoutsController < Admin::ApplicationController
    def index
      authorize FraudPayoutRun
      @runs = FraudPayoutRun.order(created_at: :desc).includes(:approved_by_user)
      @leaderboard = review_leaderboard
      @my_review_payout = pending_review_payouts.find { |row| row[:user]&.id == current_user.id }
    end

    def show
      @run = FraudPayoutRun.includes(lines: :user).find(params[:id])
      authorize @run
    end

    def approve
      @run = FraudPayoutRun.find(params[:id])
      authorize @run

      if @run.may_approve?
        @run.approved_by_user = current_user
        @run.approved_at = Time.current
        @run.approve!

        ::PaperTrail::Version.create!(
          item_type: "FraudPayoutRun",
          item_id: @run.id,
          event: "approved",
          whodunnit: current_user.id,
          object_changes: { aasm_state: %w[pending_approval approved] }.to_json
        )

        redirect_to admin_fraud_payout_path(@run), notice: "Payout run approved. #{@run.total_amount} tickets distributed to #{@run.lines.count} reviewers."
      else
        redirect_to admin_fraud_payout_path(@run), alert: "Payout run cannot be approved from its current state."
      end
    end

    def reject
      @run = FraudPayoutRun.find(params[:id])
      authorize @run

      if @run.may_reject?
        @run.reject!

        ::PaperTrail::Version.create!(
          item_type: "FraudPayoutRun",
          item_id: @run.id,
          event: "rejected",
          whodunnit: current_user.id,
          object_changes: { aasm_state: %w[pending_approval rejected] }.to_json
        )

        redirect_to admin_fraud_payout_path(@run), notice: "Payout run rejected. Orders have been released for the next run."
      else
        redirect_to admin_fraud_payout_path(@run), alert: "Payout run cannot be rejected in its current state."
      end
    end

    def trigger
      authorize FraudPayoutRun

      Fraud::CalculatePayoutsJob.perform_later(manual: true)

      redirect_to admin_fraud_payouts_path, notice: "Manual payout calculation has been queued."
    end

    private

    # All-time standings: every payout a reviewer has banked, paid or not, so
    # the board does not reset itself each time a run goes out.
    def review_leaderboard
      FraudReviewPayout.where.not(completed_at: nil).includes(:reviewer).group_by(&:reviewer).map { |reviewer, rows|
        {
          user: reviewer,
          people: rows.size,
          flags: rows.sum(&:flag_count),
          orders: rows.sum(&:order_count),
          integrities: rows.sum(&:integrity_count),
          amount: rows.sum(&:credited_amount)
        }
      }.sort_by { |row| -row[:amount] }
    end

    # What the next run will pay out, as opposed to what has been banked.
    def pending_review_payouts
      payouts = FraudReviewPayout.payable.includes(:reviewer).group_by(&:reviewer)

      payouts.map { |reviewer, rows|
        {
          user: reviewer,
          people: rows.size,
          items: rows.sum(&:item_count),
          amount: rows.sum(&:credited_amount)
        }
      }.sort_by { |row| -row[:amount] }
    end
  end
end
