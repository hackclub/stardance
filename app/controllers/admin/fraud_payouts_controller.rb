# frozen_string_literal: true

module Admin
  class FraudPayoutsController < Admin::ApplicationController
    def index
      authorize FraudPayoutRun
      @runs = FraudPayoutRun.order(created_at: :desc).includes(:approved_by_user)
      @bracket = current_bracket
      @leaderboard = decorated_leaderboard(@bracket)
      @estimated_orders, @estimated_amount = estimated_payout_for(current_user, @bracket)
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

    # Builds the live bracket standings from all reviewer activity recorded in
    # PaperTrail. Returns the BracketCalculator result hash (or nil when nobody
    # has reviewed anything yet).
    def current_bracket
      counts = reviewer_order_counts
      return nil if counts.empty?

      leaderboard = counts.map { |uid, count| { user: uid, total: count } }
      BracketCalculator.new(leaderboard, 1000).calculate
    end

    # Joins the raw bracket result rows to their User records so the view can
    # render display names without firing a query per row.
    def decorated_leaderboard(bracket)
      return [] unless bracket

      users_by_id = User.where(id: bracket[:results].map { |r| r[:user] }).index_by(&:id)
      bracket[:results].map { |row| row.merge(user_record: users_by_id[row[:user]]) }
    end

    def estimated_payout_for(user, bracket)
      return [ 0, 0 ] unless bracket

      my_result = bracket[:results].find { |r| r[:user] == user.id }
      return [ 0, 0 ] unless my_result

      [ my_result[:total], my_result[:payout].to_i ]
    end

    def reviewer_order_counts
      counts = Hash.new(0)
      FraudPayoutRun.reviewer_versions.each do |v|
        uid = FraudPayoutRun.reviewer_from_version(v)
        counts[uid] += 1 if uid
      end
      counts
    end
  end
end
