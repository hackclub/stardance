class OneTime::OpenRaffleWeekOneJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    if Raffle::Week.exists?
      Rails.logger.info "[OpenRaffleWeekOne] Raffle week already exists; skipping"
      return
    end

    Raffle::Week.create!(number: 1, status: :active, opened_at: Time.current)
    Rails.logger.info "[OpenRaffleWeekOne] Opened raffle week 1"
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info "[OpenRaffleWeekOne] Raffle week was opened by another process; skipping"
  end
end
