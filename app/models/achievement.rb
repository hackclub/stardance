# frozen_string_literal: true

Achievement = Data.define(:slug, :name, :description, :icon, :earned_check, :progress, :visibility, :secret_hint, :excluded_from_count, :stardust_reward) do
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  VISIBILITIES = %i[visible secret hidden].freeze

  def initialize(slug:, name:, description:, icon:, earned_check:, progress: nil, visibility: :visible, secret_hint: nil, excluded_from_count: false, stardust_reward: 0)
    super(slug:, name:, description:, icon:, earned_check:, progress:, visibility:, secret_hint:, excluded_from_count:, stardust_reward:)
  end

  ALL = [
    new(
      slug: :super_star,
      name: "Super Star",
      description: "Cooked so hard you ended up making a fire project that made our staff very happy!",
      icon: "fire",
      earned_check: ->(user) { user.projects.fire.exists? },
      visibility: :secret
    ),
    new(
      slug: :referral_2,
      name: "2 Friends Referred",
      description: "Referred 2 people who verified their accounts.",
      icon: "referral_2",
      earned_check: ->(user) { user.verified_referral_count >= 2 },
      progress: ->(user) { { current: [ user.verified_referral_count, 2 ].min, target: 2 } }
    ),
    new(
      slug: :referral_5,
      name: "5 Friends Referred",
      description: "Referred 5 people who verified their accounts.",
      icon: "referral_5",
      earned_check: ->(user) { user.verified_referral_count >= 5 },
      progress: ->(user) { { current: [ user.verified_referral_count, 5 ].min, target: 5 } }
    ),
    new(
      slug: :manual_outpost_ticket_approval,
      name: "Presentable Hardware Project",
      description: "Got a hardware project polished enough to show off. Unlocks the Outpost Ticket.",
      icon: "rocket",
      # Manual-only: an admin grants/revokes this via the Outpost Ticket toggle
      # on the user admin page. The achievement row is the source of truth.
      earned_check: ->(user) { user.earned_achievement?(:manual_outpost_ticket_approval) },
      visibility: :visible
    )
  ].freeze

  SECRET = (Secrets.available? ? SecretAchievements::DEFINITIONS.map { |d| new(**d) } : []).freeze

  ALL_WITH_SECRETS = (ALL + SECRET).freeze
  SLUGGED = ALL_WITH_SECRETS.index_by(&:slug).freeze
  ALL_SLUGS = SLUGGED.keys.freeze

  class << self
    def all = ALL_WITH_SECRETS

    def slugged = SLUGGED

    def all_slugs = ALL_SLUGS

    def find(slug) = SLUGGED.fetch(slug.to_sym)

    alias_method :[], :find

    def countable
      ALL_WITH_SECRETS.reject(&:excluded_from_count)
    end

    def countable_for_user(user)
      countable.select { |a| a.shown_to?(user, earned: a.earned_by?(user)) }
    end
  end

  def to_param = slug

  def persisted? = true

  def visible? = visibility == :visible
  def secret? = visibility == :secret
  def hidden? = visibility == :hidden

  def shown_to?(user, earned:)
    return true if earned
    return true if visible?
    return true if secret?

    false
  end

  def earned_by?(user) = earned_check.call(user)

  def progress_for(user)
    return nil unless progress

    progress.call(user)
  end

  def has_progress? = progress.present?

  def has_stardust_reward? = stardust_reward.positive?

  SECRET_DESCRIPTIONS = [
    "the secret to this one is... secret",
    "something's brewing... 👀",
    "this one's under wraps",
    "only the team knows this one",
    "a mystery awaits...",
    "keep building to find out!",
    "classified intel 🤫",
    "shhh... it's in the works"
  ].freeze

  def display_name(earned:)
    return name if earned || visible?

    secret? ? "???" : name
  end

  def display_description(earned:)
    return description if earned || visible?

    secret_hint || SECRET_DESCRIPTIONS.sample
  end

  def show_progress?(earned:)
    return false if earned
    return false unless has_progress?
    return false if hidden?

    true
  end
end
