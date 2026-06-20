module Raffle
  module Weeks
    class VoidDraw
      def self.run(week, reason:, ban_user: false, banned_by: nil)
        new(week, reason: reason, ban_user: ban_user, banned_by: banned_by).run
      end

      def initialize(week, reason:, ban_user: false, banned_by: nil)
        @week = week
        @reason = reason
        @ban_user = ban_user
        @banned_by = banned_by
      end

      def run
        @week.with_lock do
          return nil unless @week.drawn?

          active_draw = @week.draws.status_active.first
          unless active_draw
            active_draw = Raffle::Draw.create!(
              week: @week,
              winner_participant_id: @week.winner_participant_id,
              status: :active,
              drawn_at: @week.drawn_at || Time.current
            )
          end

          active_draw.paper_trail_event = "void_draw"
          active_draw.update!(
            status: :voided,
            void_reason: @reason,
            voided_at: Time.current
          )

          @week.paper_trail_event = "void_draw"
          @week.update!(winner_participant_id: nil, drawn_at: nil)

          if @ban_user
            user = active_draw.winner_participant.user
            if user && !user.banned?
              PaperTrail.request(whodunnit: @banned_by&.id) do
                user.ban!(reason: @reason)
              end
            end
          end

          active_draw
        end
      end
    end
  end
end
