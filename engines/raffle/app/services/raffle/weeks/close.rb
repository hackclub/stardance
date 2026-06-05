module Raffle
  module Weeks
    # Manually closes the active week (archiving it) and opens the next one,
    # unless it was the final week. Pending referrals are untouched; verified
    # referrals keep the `credited_week` they earned. Returns the new active
    # Week, or nil if the program has ended.
    class Close
      def self.run(week)
        new(week).run
      end

      def initialize(week)
        @week = week
      end

      def run
        next_week = nil
        @week.with_lock do
          return if @week.status_archived?

          @week.paper_trail_event = "close_week"
          @week.update!(status: :archived, closed_at: Time.current)
          next_number = @week.number + 1

          if next_number <= 16
            next_week = Raffle::Week.new(number: next_number, status: :active, opened_at: Time.current)
            next_week.paper_trail_event = "open_week"
            next_week.save!
          end
        end
        next_week
      end
    end
  end
end
