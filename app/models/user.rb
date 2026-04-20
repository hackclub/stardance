# == Schema Information
#
# Table name: users
#
#  id                                      :bigint           not null, primary key
#  api_key                                 :string
#  banned                                  :boolean          default(FALSE), not null
#  banned_at                               :datetime
#  banned_reason                           :text
#  club_link                               :string
#  club_name                               :string
#  cookie_clicks                           :integer          default(0), not null
#  display_name                            :string
#  email                                   :string
#  enriched_ref                            :string
#  first_name                              :string
#  flavortown_message_count_14d            :integer
#  flavortown_support_message_count_14d    :integer
#  granted_roles                           :string           default([]), not null, is an Array
#  has_gotten_free_stickers                :boolean          default(FALSE)
#  has_pending_achievements                :boolean          default(FALSE), not null
#  hcb_email                               :string
#  internal_notes                          :text
#  last_name                               :string
#  leaderboard_optin                       :boolean          default(FALSE), not null
#  manual_ysws_override                    :boolean
#  metrics_synced_at                       :datetime
#  projects_count                          :integer
#  projects_shipped_count                  :integer
#  ref                                     :string
#  regions                                 :string           default([]), is an Array
#  search_engine_indexing_off              :boolean          default(FALSE), not null
#  send_notifications_for_followed_devlogs :boolean          default(TRUE), not null
#  send_notifications_for_new_comments     :boolean          default(TRUE), not null
#  send_notifications_for_new_followers    :boolean          default(TRUE), not null
#  send_votes_to_slack                     :boolean          default(FALSE), not null
#  session_token                           :string
#  shop_region                             :enum
#  slack_balance_notifications             :boolean          default(FALSE), not null
#  slack_messages_updated_at               :datetime
#  special_effects_enabled                 :boolean          default(TRUE), not null
#  synced_at                               :datetime
#  things_dismissed                        :string           default([]), not null, is an Array
#  tutorial_steps_completed                :string           default([]), is an Array
#  verification_status                     :string           default("needs_submission"), not null
#  vote_anonymously                        :boolean          default(FALSE), not null
#  vote_balance                            :integer          default(0), not null
#  votes_count                             :integer
#  voting_locked                           :boolean          default(FALSE), not null
#  ysws_eligible                           :boolean          default(FALSE), not null
#  created_at                              :datetime         not null
#  updated_at                              :datetime         not null
#  airtable_record_id                      :string
#  slack_id                                :string
#
# Indexes
#
#  index_users_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_users_on_api_key             (api_key) UNIQUE
#  index_users_on_email               (email)
#  index_users_on_session_token       (session_token) UNIQUE
#  index_users_on_slack_id            (slack_id) UNIQUE
#
class User < ApplicationRecord
  has_paper_trail ignore: [ :projects_count, :votes_count, :updated_at, :shop_region ], on: [ :update, :destroy ]

  DISMISSIBLE_THINGS = %w[flagship_ad shop_suggestion_box willsbuilds_banner ai_coding_time_ignored_card].freeze

  has_many :identities, class_name: "User::Identity", dependent: :destroy
  has_many :achievements, class_name: "User::Achievement", dependent: :destroy
  has_one :vote_verdict, class_name: "User::VoteVerdict", dependent: :destroy
  has_many :memberships, class_name:  "Project::Membership", dependent: :destroy
  has_many :projects, through: :memberships
  has_many :hackatime_projects, class_name: "User::HackatimeProject", dependent: :destroy
  has_many :shop_orders, dependent: :destroy
  has_many :shop_card_grants, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :reports, class_name: "Project::Report", foreign_key: :reporter_id, dependent: :destroy
  has_many :project_skips, class_name: "Project::Skip", dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :ledger_entries, dependent: :destroy
  has_many :flavortime_sessions, dependent: :destroy
  has_many :project_follows, dependent: :destroy
  has_many :followed_projects, through: :project_follows, source: :project
  has_many :shop_suggestions, dependent: :destroy
  has_many :sold_items, class_name: "ShopItem::HackClubberItem", foreign_key: :user_id

  enum :verification_status, {
    needs_submission: "needs_submission",
    pending: "pending",
    verified: "verified",
    ineligible: "ineligible"
  }, default: :needs_submission, prefix: :verification

  enum :shop_region, {
    US: "US",
    EU: "EU",
    UK: "UK",
    IN: "IN",
    CA: "CA",
    AU: "AU",
    XX: "XX"
  }

  validates :verification_status, presence: true
  validates :slack_id, presence: true, uniqueness: true
  validates :hcb_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  after_commit :handle_verification_eligibility_change, if: :should_check_verification_eligibility?
  after_commit :track_identity_verified, if: :should_track_identity_verified?

  def roles = granted_roles&.map(&:to_sym) || []

  def has_role?(role_name) = roles.include?(role_name.to_sym)

  FILLOUT_CLUB_FORM_URL = "https://forms.hackclub.com/t/24dbqdeN93us"

  def fillout_club_url
    return nil if airtable_record_id.blank?
    "#{FILLOUT_CLUB_FORM_URL}?id=#{airtable_record_id}"
  end

  def club_link_uri
    return nil if club_link.blank?

    uri = URI.parse(club_link.to_s)
    uri if uri.scheme&.downcase.in?(%w[http https])
  rescue URI::InvalidURIError
    nil
  end

  def valid_club_link? = club_link_uri.present?

  def admin? = has_role?(:admin) || has_role?(:super_admin)

  def seller? = ShopItem::HackClubberItem.exists?(user_id: id)

  def can_see_deleted_devlogs? = admin? || has_role?(:fraud_dept)

  def grant_role!(role_name)
    role = role_name.to_sym
    raise ArgumentError, "Invalid role: #{role_name}" unless User::Role.all_slugs.include?(role)

    return if has_role?(role)

    update!(granted_roles: roles + [ role ])
    notify_role_granted(role)
  end

  def remove_role!(role_name)
    role = role_name.to_sym
    raise ArgumentError, "Invalid role: #{role_name}" unless User::Role.all_slugs.include?(role)

    update!(granted_roles: roles - [ role ]) if has_role?(role)
  end

  # use me! i'm full of symbols!! disregard the foul tutorial_steps_completed, she lies
  def tutorial_steps = tutorial_steps_completed&.map(&:to_sym) || []

  def tutorial_step_completed?(slug) = tutorial_steps.include?(slug)

  def complete_tutorial_step!(slug)
    update!(tutorial_steps_completed: tutorial_steps + [ slug ]) unless tutorial_step_completed?(slug)
  end

  def revoke_tutorial_step!(slug)
    update!(tutorial_steps_completed: tutorial_steps - [ slug ]) if tutorial_step_completed?(slug)
  end

  def has_dismissed?(thing_name) = things_dismissed.include?(thing_name.to_s)

  def dismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)

    update!(things_dismissed: things_dismissed + [ thing_name_str ]) unless has_dismissed?(thing_name_str)
  end

  def undismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)

    update!(things_dismissed: things_dismissed - [ thing_name_str ]) if has_dismissed?(thing_name_str)
  end

  def should_show_shop_tutorial?
    tutorial_step_completed?(:first_login) && !tutorial_step_completed?(:free_stickers)
  end

  def hackatime_identity
    identities.loaded? ? identities.find { |i| i.provider == "hackatime" } : identities.find_by(provider: "hackatime")
  end

  def hack_club_identity
    identities.loaded? ? identities.find { |i| i.provider == "hack_club" } : identities.find_by(provider: "hack_club")
  end

  class << self
    # Add more providers if needed, but make sure to include each one in PROVIDERS inside user/identity.rb; otherwise, the validation will fail.
    def find_by_hackatime(uid) = find_by_provider("hackatime", uid)
    def find_by_idv(uid)       = find_by_provider("idv", uid)

    private

    def find_by_provider(provider, uid)
      joins(:identities).find_by(user_identities: { provider:, uid: })
    end
  end

  User::Role.all_slugs.each do |role_name|
    define_method "#{role_name}?" do
      has_role?(role_name)
    end

    define_method "make_#{role_name}!" do
      grant_role!(role_name)
    end
  end

  def full_name
    [ first_name, last_name ].compact.join(" ").strip
  end

  def has_hackatime?
    identities.loaded? ? identities.any? { |i| i.provider == "hackatime" } : identities.exists?(provider: "hackatime")
  end

  def has_identity_linked? = !verification_needs_submission?

  def identity_verified? = verification_verified?

  def ysws_eligible?
    return manual_ysws_override if manual_ysws_override.in?([ true, false ])
    self[:ysws_eligible]
  end

  def eligible_for_shop? = identity_verified? && ysws_eligible?

  def should_reject_orders? = verification_ineligible? || (identity_verified? && !ysws_eligible?)

  def setup_complete?
    has_hackatime? && has_identity_linked?
  end

  def has_regions?
    regions.present? && regions.any?
  end

  def has_region?(region_code)
    regions.include?(region_code.to_s.upcase)
  end

  def regions_display
    regions.map { |r| Shop::Regionalizable.region_name(r) }.join(", ")
  end

  def all_time_coding_seconds
    try_sync_hackatime_data!&.dig(:projects)&.values&.sum || 0
  end

  def has_logged_one_hour?
    all_time_coding_seconds >= 3600
  end

  def highest_role
    roles.min_by { |r| User::Role.all_slugs.index(r) }&.to_s&.titleize || "User"
  end

  def promote_to_big_leagues!
    make_super_admin!
    make_admin!
  end

  def has_commented?
    comments.exists?
  end

  def balance = ledger_entries.sum(:amount)

  def cached_balance = Rails.cache.fetch(balance_cache_key) { balance }
  def balance_cache_key = "user/#{id}/sidebar_balance"
  def invalidate_balance_cache! = Rails.cache.delete(balance_cache_key)

  def ban!(reason: nil)
    update!(banned: true, banned_at: Time.current, banned_reason: reason)
    reject_pending_orders!(reason: reason || "User banned")
    soft_delete_projects!
  end

  def lock_voting_and_mark_votes_suspicious!(notify: false)
    return if voting_locked?

    transaction do
      update!(voting_locked: true)
      votes.update_all(suspicious: true)
    end

    if notify
      dm_user("Your voting has been locked due to suspicious activity. Please contact @Fraud Squad if you believe this is a mistake.")
    end
  end

  def reject_pending_orders!(reason: "User banned")
    shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment]).find_each do |order|
      order.mark_rejected(reason)
      order.save!
    end
  end

  def soft_delete_projects!
    projects.find_each do |project|
      project.soft_delete!(force: true)
    end
  end

  def unban!
    update!(banned: false, banned_at: nil, banned_reason: nil)
  end

  def cancel_shop_order(order_id)
    order = shop_orders.find(order_id)
    return { success: false, error: "Your order can not be canceled" } unless order.may_refund?

    order.with_lock do
      return { success: false, error: "Your order can not be canceled" } unless order.may_refund?

      order.refund!
      order.accessory_orders.each { |a| a.refund! if a.may_refund? }
    end
    { success: true, order: order }
  rescue ActiveRecord::RecordNotFound
    { success: false, error: "wuh" }
  end

  def addresses
    identity = identities.find_by(provider: "hack_club")
    return [] unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    addresses = identity_payload["addresses"] || []
    phone_number = identity_payload["phone_number"]
    addresses.map { |addr| addr.merge("phone_number" => phone_number) }
  end
  def birthday
    identity = identities.find_by(provider: "hack_club")
    return nil unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    birthday_str = identity_payload["birthday"]
    return nil if birthday_str.blank?

    Date.parse(birthday_str)
  rescue ArgumentError
    nil
  end
  def avatar
    "https://cachet.dunkirk.sh/users/#{slack_id}/r"
  end

  def grant_email
    hcb_email.presence || email
  end

  def dm_user(message)
    SendSlackDmJob.perform_later(slack_id, message)
  end

  def has_commented?
    comments.exists?
  end

  def earned_achievement_slugs
    @earned_achievement_slugs ||= achievements.pluck(:achievement_slug).to_set
  end

  def pending_achievement_notifications
    achievements.where(notified: false)
  end

  def recalculate_has_pending_achievements!
    update_column(:has_pending_achievements, achievements.where(notified: false).exists?)
  end

  def earned_achievement?(slug)
    earned_achievement_slugs.include?(slug.to_s)
  end

  def award_achievement!(slug, notified: false)
    return nil if earned_achievement?(slug)

    achievement = ::Achievement.find(slug)
    achievements.create!(achievement_slug: slug.to_s, earned_at: Time.current, notified: notified)
    @earned_achievement_slugs&.add(slug.to_s)
    update_column(:has_pending_achievements, true) unless notified
    achievement
  end

  def check_and_award_achievements!
    ::Achievement.all.each do |achievement|
      award_achievement!(achievement.slug)
    end
  end

  def generate_api_key!
    PaperTrail.request(whodunnit: -> { id || "system" }) do
      update!(api_key: "ft_sk_" + SecureRandom.hex(20))
    end
  end

  def try_sync_hackatime_data!(force: false)
    return @hackatime_data if @hackatime_data && !force

    return nil unless hackatime_identity

    result = HackatimeService.fetch_stats(hackatime_identity.uid)
    return nil unless result

    if result[:banned] && !banned?
      Rails.logger.warn "User #{id} (#{slack_id}) is banned on Hackatime, auto-banning"
      ban!(reason: "Automatically banned: User is banned on Hackatime")
      lock_voting_and_mark_votes_suspicious!
    end

    if result[:projects].any?
      User::HackatimeProject.insert_all(
        result[:projects].keys.map { |name| { user_id: id, name: name } },
        unique_by: [ :user_id, :name ]
      )
    end

    @hackatime_data = result
  end

  # we're overriding to get latest data + filter out projects w/ 0 secs!
  def hackatime_projects
    projects = super
    synced_data = try_sync_hackatime_data!
    return projects unless synced_data

    project_times = synced_data[:projects] || {}
    project_names_with_time = project_times.select { |_name, seconds| seconds.to_i > 0 }.keys
    return projects.none if project_names_with_time.empty?

    projects.where(name: project_names_with_time)
  end

  def devlog_seconds_total
    Rails.cache.fetch("user/#{id}/devlog_seconds_total", expires_in: 10.minutes) do
      devlog_postable_ids = Post.joins(:project).where(user_id: id, postable_type: "Post::Devlog")
                                .select("postable_id::bigint")
      Post::Devlog.where(id: devlog_postable_ids).not_deleted.sum(:duration_seconds) || 0
    end
  end

  def devlog_seconds_today
    Rails.cache.fetch("user/#{id}/devlog_seconds_today/#{Time.zone.today}", expires_in: 10.minutes) do
      devlog_postable_ids = Post.joins(:project).where(user_id: id, postable_type: "Post::Devlog")
                                .where(created_at: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day)
                                .select("postable_id::bigint")
      Post::Devlog.where(id: devlog_postable_ids).not_deleted.sum(:duration_seconds) || 0
    end
  end

  def has_shipped?
    projects.joins(:ship_events).exists?
  end

  def shipped_projects_count_in_range(start_date, end_date)
    projects
      .joins(:posts)
      .where(posts: { postable_type: "Post::ShipEvent" })
      .where(posts: { created_at: start_date.beginning_of_day..end_date.end_of_day })
      .distinct
      .count
  end

  def reject_awaiting_verification_orders!
    shop_orders.where(aasm_state: "awaiting_verification").find_each do |order|
      reason = if verification_ineligible?
                 "Identity verification marked as ineligible"
      else
                 "Not eligible for YSWS"
      end
      order.mark_rejected!(reason)
    end
  end

  def apply_hca_verification_payload!(payload, persist_with_callbacks: true)
    status = payload["verification_status"].to_s
    return :invalid_status unless self.class.verification_statuses.key?(status)

    fatal_rejection = payload["fatal_rejection"] == true
    return :ignored_ineligible if status == "ineligible" && !fatal_rejection
    fatal_ineligible = status == "ineligible" && fatal_rejection

    ysws_eligible = payload["ysws_eligible"] == true
    attrs = { verification_status: status, ysws_eligible: ysws_eligible }
    changed = attrs.any? { |key, value| self[key] != value }

    if changed
      if persist_with_callbacks
        update!(attrs)
      else
        update_columns(attrs.merge(updated_at: Time.current))
      end
    end

    enforce_fatal_rejection! if fatal_ineligible

    return :fatal_ineligible if fatal_ineligible
    return :updated if changed

    :unchanged
  end

  private

  def should_check_verification_eligibility?
    saved_change_to_verification_status? || saved_change_to_ysws_eligible?
  end

  def handle_verification_eligibility_change
    if eligible_for_shop?
      Shop::ProcessVerifiedOrdersJob.perform_later(id)
    elsif should_reject_orders?
      reject_awaiting_verification_orders!
    end
  end

  def should_track_identity_verified?
    saved_change_to_verification_status? && verification_verified?
  end

  def track_identity_verified
    FunnelTrackerService.track(
      event_name: "identity_verified",
      user: self
    )
  end

  def notify_role_granted(role)
    return if Rails.env.development?
    return unless slack_id.present?

    role_info = User::Role.find(role)
    message = "🎉 Congratulations! You've been granted the *#{role_info.name.to_s.titleize}* role on Stardance."
    dm_user(message)
  end

  def enforce_fatal_rejection!
    reject_awaiting_verification_orders!
    return if banned?

    update_columns(
      banned: true,
      banned_at: Time.current,
      banned_reason: "Fatal identity verification rejection",
      updated_at: Time.current
    )
  end
end
