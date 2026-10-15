# frozen_string_literal: true

module BukuX3
  # Save the first observed global flag activation. Preserve any previously
  # captured cutoff so existing ships never move between phases.
  class Unlock
    def self.call
      return unless Flipper.enabled?(:bukux3)
      event = Event.current
      return event if event&.unlocked_at?

      event ||= Event.create_or_find_by!(key: Event::KEY)
      event.with_lock do
        if !event.unlocked_at?
          event.update!(unlocked_at: Time.current, destruction_minutes: Event::STARTING_DESTRUCTION_MINUTES)
        end
      end
      event
    end
  end
end
