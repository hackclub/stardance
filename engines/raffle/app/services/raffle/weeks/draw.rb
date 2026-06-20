module Raffle
  module Weeks
    class Draw
      def self.run(week)
        new(week).run
      end

      def initialize(week)
        @week = week
      end

      def run
        @week.with_lock do
          return nil if @week.drawn?
          return nil unless @week.status_active? || @week.status_archived?

          all_standings = @week.standings
          participants = Raffle::Participant.includes(:user).where(id: all_standings.keys).index_by(&:id)
          eligible_standings = all_standings.select { |pid, _| participants[pid]&.eligible? }

          excluded_ids = @week.voided_winner_ids
          eligible_standings = eligible_standings.reject { |pid, _| excluded_ids.include?(pid) } if excluded_ids.any?

          return nil if eligible_standings.empty?

          total = eligible_standings.values.sum
          roll = SecureRandom.random_number(total)

          winner_id = nil
          cumulative = 0
          eligible_standings.each do |pid, entries|
            cumulative += entries
            if roll < cumulative
              winner_id = pid
              break
            end
          end

          return nil unless winner_id

          now = Time.current

          @week.paper_trail_event = "draw_winner"
          @week.update!(
            winner_participant_id: winner_id,
            drawn_at: now
          )

          Raffle::Draw.create!(
            week: @week,
            winner_participant: participants[winner_id],
            status: :active,
            drawn_at: now
          )

          @week.winner_participant
        end
      end
    end
  end
end
