# frozen_string_literal: true

# The rng widget and page post here to roll; the leaderboard action renders
# /rng (day-browsable board), and history renders /rng/history (your rolls).
class DailyRollsController < ApplicationController
  PAGE_SIZE = 50

  # Surfaces that render the reroll control, mapped to their button size. Used
  # to validate the reroll_status poll param so it can't render arbitrary sizes.
  REROLL_SURFACE_SIZES = { "rng-hero" => :large, "daily-roll-widget" => :small }.freeze

  before_action :require_week_2_release

  def create
    authorize :daily_roll

    streams = current_user ? roll_for_user : roll_for_anonymous

    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.html { redirect_back fallback_location: current_user ? home_path : rng_path }
    end
  end

  # The earned second roll: unlocked once the user has coded > 5 min today on
  # a linked Stardance project. Its value is added to the first roll (their
  # board number becomes the sum), so coding can only ever help.
  def reroll
    authorize :daily_roll

    roll = current_user && DailyRoll.for_today(current_user)
    just_rerolled = false

    if reroll_allowed?(roll)
      # Conditional update so a double-click can't stack a second reroll.
      just_rerolled = DailyRoll.where(id: roll.id, reroll_value: nil)
                               .update_all(reroll_value: DailyRoll.random_value, updated_at: Time.current).positive?
      roll.reload
    end

    # Nothing to show if they were never eligible (also blocks a direct POST).
    head :forbidden and return unless roll&.rerolled?

    respond_to do |format|
      format.turbo_stream { render turbo_stream: reroll_streams(roll, just_rerolled) }
      format.html { redirect_back fallback_location: rng_path }
    end
  end

  # Polled (plain fetch) by the locked reroll button so it can flip to unlocked
  # in place once today's coding time crosses the threshold — no page reload.
  # Re-kicks the throttled streak sync so a surface that never ran it (e.g. the
  # rail widget on the home page) still gets fresh data while the user waits.
  def reroll_status
    authorize :daily_roll, :reroll?

    size = REROLL_SURFACE_SIZES[params[:surface]]
    head :not_found and return unless size && Flipper.enabled?(:rng_reroll, current_user)

    current_user.sync_streak_if_stale!

    roll = DailyRoll.for_today(current_user)
    head :no_content and return unless roll

    render partial: "daily_rolls/reroll_control",
           locals: { user: current_user, roll: roll, block: params[:surface], size: size }
  end

  # Dev/test only (see routes): wipe today's roll so the reveal can be
  # re-tested without waiting for midnight.
  def clear
    head :not_found and return unless Rails.env.development? || Rails.env.test?
    authorize :daily_roll, :create?

    DailyRoll.where(user: current_user, rolled_on: Date.current).delete_all
    redirect_back fallback_location: rng_path
  end

  def leaderboard
    authorize :daily_roll

    # Refresh today's coding time on every /rng visit so the reroll unlocks
    # promptly after coding — but once they've coded enough to unlock there's
    # nothing more to learn, so stop hitting Hackatime.
    if current_user && Flipper.enabled?(:rng_reroll, current_user) && !reroll_unlocked?(current_user)
      current_user.sync_streak!
    end

    @body_class = "app-layout-page"
    @today = Date.current
    @earliest_date = DailyRoll.minimum(:rolled_on) || @today
    @date = requested_date
    @total_count = DailyRoll.on(@date).count
    @total_pages = [ (@total_count.to_f / PAGE_SIZE).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @offset = (@page - 1) * PAGE_SIZE
    # Only ever loads one page of rows, so a 50k-roll day can't blow up.
    @rolls = DailyRoll.leaderboard(@date, limit: PAGE_SIZE, offset: @offset)

    if current_user
      @viewer_today_roll = DailyRoll.for_today(current_user)
      @viewer_date_roll = @date == @today ? @viewer_today_roll : DailyRoll.find_by(user: current_user, rolled_on: @date)
      if @viewer_date_roll
        @viewer_rank = @viewer_date_roll.rank
        @viewer_page = ((@viewer_rank - 1) / PAGE_SIZE) + 1
      end
    else
      @anonymous_roll = AnonymousRoll.new(cookies).today
    end

    record = DailyRoll.ranked.includes(:user).first
    # Today's leader is already on the podium; the record line is only
    # interesting when it points somewhere else.
    @record = record if record && record.rolled_on != @today
  end

  def history
    authorize :daily_roll, :history? # signed in only — no history for guests-of-cookie

    @body_class = "app-layout-page"
    @today = Date.current
    @stats = viewer_stats
    @history = DailyRoll.where(user: current_user).order(rolled_on: :desc).limit(365)
  end

  private

  # Signed-in: one real roll per day, streamed to the rail widget + hero.
  def roll_for_user
    already_rolled = DailyRoll.for_today(current_user).present?
    roll = DailyRoll.roll!(current_user)
    # Whichever surface isn't on the page is a no-op replace by missing id.
    [
      turbo_stream.replace(
        "daily-roll-widget",
        DiscoverRail::DailyRollWidget.new(user: current_user, context: { just_rolled: !already_rolled }).render_in(view_context)
      ),
      turbo_stream.replace(
        "rng-hero",
        partial: "daily_rolls/hero",
        locals: { roll: roll, just_rolled: !already_rolled }
      )
    ]
  end

  # Logged-out: one cookie-backed roll per day. It lives in a signed cookie
  # (never the DB, so it stays off the leaderboard) and is cleared on
  # sign-in so the user gets a fresh real roll.
  def roll_for_anonymous
    anon = AnonymousRoll.new(cookies)
    roll = anon.today
    just_rolled = roll.nil?
    roll = anon.store(DailyRoll.random_value) if just_rolled

    [ turbo_stream.replace("rng-hero", partial: "daily_rolls/hero",
                           locals: { roll: roll, just_rolled: just_rolled, anonymous: true }) ]
  end

  # Server-side gate for the reroll (never trust the button's state): signed
  # in, feature live, has rolled today, hasn't already rerolled, and has coded
  # past the unlock threshold today on a linked Stardance project.
  def reroll_allowed?(roll)
    current_user.present? &&
      Flipper.enabled?(:rng_reroll, current_user) &&
      roll.present? && !roll.rerolled? &&
      reroll_unlocked?(current_user)
  end

  # Has the user coded enough today to unlock the reroll? Coding time only ever
  # accumulates, so once this is true it stays true for the rest of the day.
  def reroll_unlocked?(user)
    user.streak_today_activity&.coded_seconds.to_i > DailyRoll::REROLL_MIN_SECONDS
  end

  # Replace both rng surfaces with the post-reroll state; just_rerolled drives
  # the digit-reveal animation up to the new summed total.
  def reroll_streams(roll, just_rerolled)
    [
      turbo_stream.replace(
        "daily-roll-widget",
        DiscoverRail::DailyRollWidget.new(user: current_user, context: { just_rolled: just_rerolled }).render_in(view_context)
      ),
      turbo_stream.replace(
        "rng-hero",
        partial: "daily_rolls/hero",
        locals: { roll: roll, just_rolled: just_rerolled }
      )
    ]
  end

  # rng ships with the week 2 release; until then it 404s for everyone.
  def require_week_2_release
    head :not_found unless Flipper.enabled?(:week_2_release, current_user)
  end

  # /rng?date=2026-06-10 — clamped to days that can have rolls.
  def requested_date
    date = Date.iso8601(params[:date].to_s)
    date.clamp(@earliest_date, @today)
  rescue Date::Error
    @today
  end

  def viewer_stats
    rolls = DailyRoll.where(user: current_user)
    best = rolls.ranked.first
    worst = rolls.order(Arel.sql("(#{DailyRoll::TOTAL_SQL}) ASC, daily_rolls.created_at ASC")).first
    return nil unless best

    { best: best, worst: worst, count: rolls.count, total: rolls.sum(Arel.sql(DailyRoll::TOTAL_SQL)) }
  end
end
