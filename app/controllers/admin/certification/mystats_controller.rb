# frozen_string_literal: true

class Admin::Certification::MystatsController < Admin::Certification::ApplicationController
  before_action :set_body_class

  def show
    authorize :mystats, policy_class: Admin::Certification::MystatsPolicy

    @reviews = Certification::Ship
      .where(reviewer_id: current_user.id)
      .where.not(status: :pending)
      .includes(:project)
      .order(decided_at: :desc)
      .to_a

    @payouts = ReviewerPayoutRequest
      .where(user_id: current_user.id, aasm_state: "paid")
      .order(paid_at: :desc)

    @unclaimed = ReviewerPayoutRequest.unclaimed_for(current_user)
    @pending_request = ReviewerPayoutRequest.pending_for(current_user)

    @total_count = @reviews.size
    @approved_count = @reviews.count(&:approved?)
    @returned_count = @reviews.count(&:returned?)
    @approval_rate = @total_count.zero? ? 0 : (@approved_count * 100.0 / @total_count).round

    # adding reviews/payouts in one log
    @history_items = []

    @reviews.each do |review|
      @history_items << {
        type: :review,
        title: review.project.title,
        id: review.id,
        path: admin_certification_ship_path(review),
        status: review.status,
        amount: review.stardust_earned || 0,
        date: review.decided_at
      }
    end

    @payouts.each do |payout|
      @history_items << {
        type: :payout,
        title: "Payout",
        id: payout.id,
        path: nil,
        status: :paid,
        amount: payout.amount,
        date: payout.paid_at
      }
    end

    @history_items.sort_by! { |item| item[:date] || Time.at(0) }.reverse!
  end

  def create_payout_request
    authorize :mystats, :create_payout_request?, policy_class: Admin::Certification::MystatsPolicy

    @request = ReviewerPayoutRequest.new(
      user: current_user,
      amount: params[:amount].to_i
    )

    if @request.save
      redirect_to admin_certification_mystats_path, notice: "Payout request submitted!"
    else
      redirect_to admin_certification_mystats_path, alert: @request.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to admin_certification_mystats_path, alert: "You already have a pending payout request"
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end
end
