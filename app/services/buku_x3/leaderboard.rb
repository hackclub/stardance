module BukuX3
  class Leaderboard
    LIMIT = 25
    PRIZE_PLACES = 5
    Entry = Data.define(:user, :minutes)

    def initialize(event)
      @event = event
    end

    def teams
      return { buku: [], bean: [] } unless @event&.active?

      # Reuse accounting corrections and team snapshots without assigning roles
      # or refreshing event accounting from a public page request.
      visible_users = User.on_leaderboard.where(
        "users.things_dismissed @> ARRAY[?]::varchar[]", BukuX3RevealComponent::DISMISS_THING
      )
      contributions = @event.contributions.where(user_id: visible_users.select(:id)).where("minutes > 0")
      totals = { buku: true, bean: false }.transform_values do |buku|
        contributions.where(buku: buku).group(:user_id)
          .order(Arel.sql("SUM(minutes) DESC"), :user_id).limit(LIMIT)
          .pluck(:user_id, Arel.sql("SUM(minutes)"))
      end
      users = User.where(id: totals.values.flatten(1).map(&:first)).index_by(&:id)
      totals.transform_values do |rows|
        rows.filter_map { |id, minutes| Entry.new(user: users[id], minutes: minutes) if users[id] }
      end
    end
  end
end
