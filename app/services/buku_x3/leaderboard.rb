module BukuX3
  class Leaderboard
    LIMIT = 25
    PRIZE_PLACES = 5
    Entry = Data.define(:user, :minutes)
    Own = Data.define(:team, :entry, :rank) do
      # The rank just above the viewer and the minutes needed to pass it.
      # Unranked viewers chase the last listed spot, unless they already have
      # more minutes (opted out of the leaderboard), so there is nothing to chase.
      def chase(teams)
        entries = teams[team]
        target_rank = rank ? rank - 1 : entries.size
        return unless target_rank.positive?

        target = entries[target_rank - 1]
        return if rank.nil? && entry.minutes > target.minutes

        [ target_rank, [ target.minutes - entry.minutes, 1 ].max ]
      end
    end

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

    # The viewer's own standing, even when unranked (opted out or past LIMIT).
    # Skipped before the reveal so the page never spoils their team.
    def own(user, teams)
      return unless user && @event&.active? && user.has_dismissed?(BukuX3RevealComponent::DISMISS_THING)

      team = Assignment.buku?(user) ? :buku : :bean
      index = teams[team].index { |entry| entry.user.id == user.id }
      return Own.new(team:, entry: teams[team][index], rank: index + 1) if index

      minutes = @event.contributions.where(user: user, buku: team == :buku).sum(:minutes)
      Own.new(team:, entry: Entry.new(user: user, minutes: minutes), rank: nil)
    end
  end
end
