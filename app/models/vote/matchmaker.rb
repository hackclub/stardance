class Vote::Matchmaker
  EARLIEST_WEIGHT = 60
  HOURS_GATE_MULTIPLIER = 3
  HOURS_GATE_EXEMPT_AFTER = 50.0
  PAID_FALLBACK_SAMPLE_SIZE = 50

  EXCLUDED_CATEGORIES_BY_OS = {
    windows: [ "Desktop App (Linux)", "Desktop App (macOS)" ],
    mac: [ "Desktop App (Windows)" ],
    linux: [ "Desktop App (Windows)" ],
    android: [ "Desktop App (Windows)", "Desktop App (Linux)", "Desktop App (macOS)", "iOS App" ],
    ios: [ "Desktop App (Windows)", "Desktop App (Linux)", "Desktop App (macOS)", "Android App" ]
  }.freeze

  def initialize(user, user_agent: nil)
    @user = user
    @user_agent = user_agent
  end

  def next_ship_event
    next_unpaid_ship_event || paid_fallback_ship_event
  end

  def next_unpaid_ship_event
    pick_from(gated_pool) || pick_from(ungated_pool)
  end

  private
    def pick_from(pool)
      if rand(100) < EARLIEST_WEIGHT
        earliest_in(pool) || near_payout_in(pool)
      else
        near_payout_in(pool) || earliest_in(pool)
      end
    end

    def earliest_in(pool)
      pool.order(:created_at, Arel.sql("RANDOM()")).first
    end

    def near_payout_in(pool)
      pool.order(votes_count: :desc, created_at: :asc).first
    end

    def gated_pool
      if gate_exempt?
        ungated_pool
      else
        ungated_pool.where(hours_at_ship: ..hours_cap)
      end
    end

    def gate_exempt?
      voter_hours >= HOURS_GATE_EXEMPT_AFTER
    end

    def hours_cap
      voter_hours * HOURS_GATE_MULTIPLIER
    end

    def voter_hours
      @voter_hours ||= @user.approved_ship_events.sum(:hours_at_ship).to_f
    end

    def ungated_pool
      candidate_ship_events.voteable
    end

    def paid_fallback_ship_event
      candidate_ship_events
        .paid_out
        .order(created_at: :desc)
        .limit(PAID_FALLBACK_SAMPLE_SIZE)
        .sample
    end

    def candidate_ship_events
      scope = Post::ShipEvent
        .joins(:project)
        .where.not(id: @user.votes.select(:ship_event_id))
        .where.not(id: @user.vote_assignments.select(:ship_event_id))
        .where.not(posts: { project_id: @user.projects.select(:id) })
        .where.not(posts: { project_id: @user.project_skips.select(:project_id) })
        .where.not(posts: { project_id: @user.reports.select(:project_id) })

      excluded_categories.each do |category|
        scope = scope.where.not("? = ANY(projects.project_categories)", category)
      end

      scope
    end

    def excluded_categories
      EXCLUDED_CATEGORIES_BY_OS[detect_os] || []
    end

    def detect_os
      if @user_agent
        user_agent = @user_agent.downcase

        if user_agent.include?("android")
          :android
        elsif user_agent.include?("iphone") || user_agent.include?("ipod") || user_agent.include?("ipad")
          :ios
        elsif user_agent.include?("macintosh") && (user_agent.include?("mobile") || user_agent.include?("cpu os"))
          :ios
        elsif user_agent.include?("windows")
          :windows
        elsif user_agent.include?("macintosh")
          :mac
        elsif user_agent.include?("linux")
          :linux
        end
      end
    end
end
