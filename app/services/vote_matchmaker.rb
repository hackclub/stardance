class VoteMatchmaker
  EXCLUDED_CATEGORIES_BY_OS = {
    windows: [ "Desktop App (Linux)", "Desktop App (macOS)" ],
    mac: [ "Desktop App (Windows)" ],
    linux: [ "Desktop App (Windows)" ],
    android: [ "Desktop App (Windows)", "Desktop App (Linux)", "Desktop App (macOS)", "iOS App" ],
    ios: [ "Desktop App (Windows)", "Desktop App (Linux)", "Desktop App (macOS)", "Android App" ]
  }.freeze

  EARLIEST_WEIGHT = 60
  NEAR_PAYOUT_WEIGHT = 40

  def initialize(user, user_agent: nil)
    @user = user
    @os = detect_os(user_agent)
  end

  def next_ship_event
    result = if rand(100) < EARLIEST_WEIGHT
      find_earliest_ship_event || find_near_payout_ship_event
    else
      find_near_payout_ship_event || find_earliest_ship_event
    end

    result || (@user.vote_balance.negative? ? find_paid_fallback_ship_event : nil)
  end

  private

  def detect_os(ua)
    return nil unless ua
    s = ua.downcase

    return :android if s.include?("android")
    return :ios if s.include?("iphone") || s.include?("ipod") || s.include?("ipad")
    if s.include?("macintosh") && (s.include?("mobile") || s.include?("cpu os") || s.include?("ipad"))
      return :ios
    end

    return :windows if s.include?("windows")
    return :mac if s.include?("macintosh")
    return :linux if s.include?("linux")
    nil
  end

  def excluded_categories
    EXCLUDED_CATEGORIES_BY_OS[@os] || []
  end

  def find_earliest_ship_event
    voteable_ship_events.order(:created_at, "RANDOM()").find { |ship_event| ship_event.hours.to_f.positive? }
  end

  def find_near_payout_ship_event
    voteable_ship_events.order(votes_count: :desc, created_at: :asc).find { |ship_event| ship_event.hours.to_f.positive? }
  end

  def base_ship_events
    Post::ShipEvent
      .current_voting_scale
      .joins(:project)
      .where(certification_status: "approved")
      .where.not(id: @user.votes.select(:ship_event_id))
      .where.not(projects: { id: @user.projects })
      .where.not(projects: { id: @user.reports.select(:project_id) })
      .where.not(projects: { id: @user.project_skips.select(:project_id) })
  end

  def voteable_ship_events
    scope = base_ship_events
      .where(payout: nil)
      .where.not(id: full_ship_event_ids)
      .where.not(id: vote_deficit_blocked_ship_event_ids)

    excluded_categories.each do |category|
      scope = scope.where.not("? = ANY(projects.project_categories)", category)
    end

    scope
  end

  def vote_deficit_blocked_ship_event_ids
    Post::ShipEvent
      .joins(post: :user)
      .where(id: Vote.payout_countable.group(:ship_event_id).having("COUNT(*) >= ?", Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT).select(:ship_event_id))
      .where("users.vote_balance < 0")
      .select("post_ship_events.id")
  end

  def find_paid_fallback_ship_event
    base_ship_events
      .where.not(payout: nil)
      .order(created_at: :desc)
      .limit(50)
      .sample
  end

  def full_ship_event_ids
    Vote
      .payout_countable
      .group(:ship_event_id)
      .having("COUNT(*) >= ?", Post::ShipEvent::VOTES_TO_LEAVE_POOL)
      .select(:ship_event_id)
  end
end
