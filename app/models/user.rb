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
#  granted_roles                :string           default([]), not null, is an Array
#  has_gotten_free_stickers     :boolean          default(FALSE)
#  has_pending_achievements     :boolean          default(FALSE), not null
#  hcb_email                    :string
#  interests                    :string           default([]), is an Array
#  internal_notes               :text
#  last_name                    :string
#  manual_ysws_override         :boolean
#  mission_review_notifications :boolean          default(TRUE), not null
#  onboarded_at                 :datetime
#  ref                          :string
#  regions                      :string           default([]), is an Array
#  session_token                :string
#  shop_region                  :enum
#  synced_at                    :datetime
#  things_dismissed             :string           default([]), not null, is an Array
#  verification_status          :string           default("needs_submission"), not null
#  vote_balance                 :integer          default(0), not null
#  votes_count                  :integer
#  voting_locked                :boolean          default(FALSE), not null
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
  has_paper_trail ignore: [ :votes_count, :updated_at, :shop_region ], on: [ :update, :destroy ]

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

  enum :experience_level, {
    none: "none",
    little: "little",
    some: "some",
    experienced: "experienced"
  }, prefix: :experience

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

  scope :discoverable, -> { joins(:hack_club_identity).distinct }

  validates :banner, content_type: [ "image/png", "image/jpeg", "image/webp", "image/gif" ],
                     size: { less_than: 8.megabytes }
  validates :bio, length: { maximum: 1000 }
  validates :verification_status, presence: true
  validates :slack_id, uniqueness: true, allow_nil: true
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :display_name, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :display_name, length: { maximum: 30 }, allow_blank: true
  validates :hcb_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  include User::Notifications
  include User::Roles
  include User::Identities
  include User::Verification
  include User::HackatimeSync
  include User::ShopAccess
  include User::Wallet
  include User::Moderation
  include User::Achievements
  include User::StateFlags
  include User::Social
  include User::Profile
  include User::Preferences

  KERBAL_FIRST_NAMES = %w[
    Jebediah Bill Bob Valentina Lodwig Shepard Gus Wernher Gene
    Mortimer Linus Genekin Bobnik Billard Valentik Aldler Orlas
    Neilbur Buzzig Mikevin Aldous Yurgus Laikus Grissom Shepnik
    Aldorf Scottbert Rodbur Danwig Franklis Aldwig Gordox
  ].freeze

  def self.random_funny_display_name
    "#{KERBAL_FIRST_NAMES.sample} Kerman #{rand(1000..9999)}"
  end

  private

  def interests_must_be_allowed
    return if interests.blank?
    return if Array(interests) == [ INTERESTS_UNKNOWN ]
    invalid = Array(interests) - ALLOWED_INTERESTS
    errors.add(:interests, "contains invalid values: #{invalid.join(', ')}") if invalid.any?
  end
end
