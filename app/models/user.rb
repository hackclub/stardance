# == Schema Information
#
# Table name: users
#
#  id                           :bigint           not null, primary key
#  age_attestation              :string
#  banned                       :boolean          default(FALSE), not null
#  banned_at                    :datetime
#  banned_reason                :text
#  bio                          :text
#  display_name                 :string
#  email                        :string
#  enriched_ref                 :string
#  experience_level             :string
#  first_name                   :string
#  geocoded_country             :string
#  geocoded_lat                 :float
#  geocoded_lon                 :float
#  geocoded_subdivision         :string
#  granted_roles                :string           default([]), not null, is an Array
#  guest_email                  :string
#  has_gotten_free_stickers     :boolean          default(FALSE)
#  has_pending_achievements     :boolean          default(FALSE), not null
#  hcb_email                    :string
#  interests                    :string           default([]), is an Array
#  internal_notes               :text
#  ip_address                   :string
#  last_name                    :string
#  manual_ysws_override         :boolean
#  mission_review_notifications :boolean          default(TRUE), not null
#  onboarded_at                 :datetime
#  ref                          :string
#  regions                      :string           default([]), is an Array
#  session_token                :string
#  shop_region                  :enum
#  shop_tutorial_completed_at   :datetime
#  shop_tutorial_started_at     :datetime
#  synced_at                    :datetime
#  things_dismissed             :string           default([]), not null, is an Array
#  user_agent                   :string
#  user_ref                     :string
#  verification_checked_at      :datetime
#  verification_status          :string           default("needs_submission"), not null
#  vote_balance                 :integer          default(0), not null
#  votes_count                  :integer
#  ysws_eligible                :boolean          default(FALSE), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  slack_id                     :string
#
# Indexes
#
#  index_users_on_email                      (email)
#  index_users_on_lower_display_name_unique  (lower((display_name)::text)) UNIQUE WHERE ((display_name IS NOT NULL) AND ((display_name)::text <> ''::text))
#  index_users_on_lower_email_unique         (lower((email)::text)) UNIQUE WHERE ((email IS NOT NULL) AND ((email)::text <> ''::text))
#  index_users_on_onboarded_at               (onboarded_at)
#  index_users_on_session_token              (session_token) UNIQUE
#  index_users_on_slack_id                   (slack_id) UNIQUE
#
class User < ApplicationRecord
  include SemanticSearchIndexable
  include Gorse::SyncableUser

  has_paper_trail ignore: [ :votes_count, :updated_at, :shop_region, :ip_address, :user_agent ], on: [ :update, :destroy ]
  semantic_search_indexable type: "user"

  has_many :identities, class_name: "User::Identity", dependent: :destroy
  has_one :hackatime_identity, -> { hackatime }, class_name: "User::Identity"
  has_one :hack_club_identity, -> { hack_club }, class_name: "User::Identity"
  has_many :achievements, class_name: "User::Achievement", dependent: :destroy
  has_many :pending_achievement_notifications, -> { where(notified: false) }, class_name: "User::Achievement"
  has_one :vote_verdict, class_name: "User::VoteVerdict", dependent: :destroy
  has_many :memberships, class_name: "Project::Membership", dependent: :destroy
  has_many :projects, through: :memberships
  has_many :shipped_projects, -> { with_ship_events }, through: :memberships, source: :project
  has_many :hackatime_projects, class_name: "User::HackatimeProject", dependent: :destroy
  has_many :shop_orders, dependent: :destroy
  has_many :shop_card_grants, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :vote_assignments, class_name: "Vote::Assignment", dependent: :destroy
  has_many :reports, class_name: "Project::Report", foreign_key: :reporter_id, dependent: :destroy
  has_many :project_skips, class_name: "Project::Skip", dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :ledger_entries, dependent: :destroy
  has_many :project_follows, dependent: :destroy
  has_many :followed_projects, through: :project_follows, source: :project
  has_one :preference, class_name: "User::Preference", dependent: :destroy

  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy, inverse_of: :follower
  has_many :follows_as_followed, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy, inverse_of: :followed
  has_many :following, through: :follows_as_follower, source: :followed
  has_many :followers, through: :follows_as_followed, source: :follower

  has_many :mission_memberships, class_name: "Mission::Membership", dependent: :destroy
  has_many :owned_missions,      -> { merge(Mission::Membership.owner_role) },
           through: :mission_memberships, source: :mission
  has_many :reviewable_missions, -> { merge(Mission::Membership.reviewer_role) },
           through: :mission_memberships, source: :mission
  has_many :reviewed_mission_submissions, class_name: "Mission::Submission",
           foreign_key: :reviewed_by_id, dependent: :nullify
  has_many :shop_suggestions, dependent: :destroy
  has_many :shop_wishlists, dependent: :destroy
  has_many :wishlisted_shop_items, through: :shop_wishlists, source: :shop_item
  has_many :sold_items, class_name: "ShopItem::HackClubberItem", foreign_key: :user_id

  has_one_attached :banner

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

  attribute :age_attestation, :string
  attribute :experience_level, :string

  enum :age_attestation, {
    teen_13_18: "teen_13_18",
    ineligible: "ineligible"
  }, prefix: :age_attestation

  def age_blocked?
    age_attestation_ineligible? && manual_ysws_override != true
  end

  enum :experience_level, {
    none: "none",
    little: "little",
    some: "some",
    experienced: "experienced"
  }, prefix: :experience

  USER_REF_OPTIONS = Rsvp::USER_REF_OPTIONS

  ALLOWED_INTERESTS = %w[web_dev hardware app_dev game_dev ai_ml art_design].freeze
  INTEREST_LABELS = {
    "web_dev" => "Websites",
    "game_dev" => "Video games",
    "app_dev" => "Desktop applications",
    "hardware" => "Hardware/<wbr>electronics".html_safe,
    "ai_ml" => "AI/<wbr>machine learning".html_safe,
    "art_design" => "Art & design"
  }.freeze
  INTERESTS_UNKNOWN = "dont_know".freeze

  validate :interests_must_be_allowed
  after_commit :enqueue_geocode_job, on: :create

  scope :discoverable, -> { joins(:hack_club_identity).distinct }

  validates :banner, content_type: [ "image/png", "image/jpeg", "image/webp", "image/gif" ],
                     size: { less_than: 8.megabytes }
  validates :bio, length: { maximum: 1000 }
  validates :verification_status, presence: true
  validates :slack_id, uniqueness: true, allow_nil: true
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  MAX_DISPLAY_NAME_LENGTH = 30
  USERNAME_FORMAT = /\A[a-zA-Z0-9_-]+\z/

  validates :display_name, presence: true
  validates :display_name, uniqueness: { case_sensitive: false }
  # Length/format only apply when the name is actually being set or changed
  # (onboarding name step, profile rename). Existing/HCA accounts can carry
  # legacy names with spaces or other characters — enforcing the new format on
  # every save would block them from logging in (user.save! in the HCA login
  # flow would raise RecordInvalid → "Unable to save your account").
  validates :display_name, length: { maximum: MAX_DISPLAY_NAME_LENGTH }, if: :display_name_changed?
  validates :display_name, format: { with: USERNAME_FORMAT, message: "can only contain letters, numbers, hyphens, and underscores" }, if: :display_name_changed?
  validates :hcb_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :user_ref, length: { maximum: 100 }, allow_blank: true

  include User::Notifications
  include User::Roles
  include User::Identities
  include User::Verification
  include User::HackatimeSync
  include User::ShopAccess
  include User::ShopTutorial
  include User::Wallet
  include User::Moderation
  include User::Achievements
  include User::StateFlags
  include User::Social
  include User::Profile
  include User::Preferences
  include User::UsernameBloomSync

  after_create_commit :increment_signup_counter, if: -> { Flipper.enabled?(:new_onboarding) }

  KERBAL_FIRST_NAMES = %w[
    Jebediah Bill Bob Valentina Lodwig Shepard Gus Wernher Gene
    Mortimer Linus Genekin Bobnik Billard Valentik Aldler Orlas
    Neilbur Buzzig Mikevin Aldous Yurgus Laikus Grissom Shepnik
    Aldorf Scottbert Rodbur Danwig Franklis Aldwig Gordox
  ].freeze

  def self.random_funny_display_name
    "#{KERBAL_FIRST_NAMES.sample}_Kerman_#{rand(1000..9999)}"
  end

  # Auto-assigned placeholder name for a guest who hasn't picked one yet: the
  # email's local part plus a random number (e.g. "ada_lovelace_4821"). Trimmed
  # to fit MAX_DISPLAY_NAME_LENGTH and the USERNAME_FORMAT; falls back to a
  # Kerbal name when the local part has no usable characters.
  def self.placeholder_display_name_from_email(email)
    local = email.to_s.split("@").first.to_s
                 .gsub(/[^a-zA-Z0-9_-]/, "_")
                 .gsub(/_{2,}/, "_")
                 .delete_prefix("_").delete_suffix("_")
    return random_funny_display_name if local.blank?

    "#{local.first(MAX_DISPLAY_NAME_LENGTH - 5)}_#{rand(1000..9999)}"
  end

  def active_project_for_mission(mission)
    return nil if mission.nil?
    projects
      .joins(:mission_attachments)
      .where(project_mission_attachments: { mission_id: mission.id, detached_at: nil })
      .where(deleted_at: nil)
      .order("project_mission_attachments.attached_at DESC")
      .first
  end

  private

  def increment_signup_counter
    Rails.cache.increment("landing/signup_count", 1, expires_in: 30.seconds)
  end

  def enqueue_geocode_job
    UserGeocodeJob.perform_later(id) if ip_address.present?
  end

  def interests_must_be_allowed
    return if interests.blank?
    return if Array(interests) == [ INTERESTS_UNKNOWN ]
    invalid = Array(interests) - ALLOWED_INTERESTS
    errors.add(:interests, "contains invalid values: #{invalid.join(', ')}") if invalid.any?
  end
end
