# == Schema Information
#
# Table name: projects
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  ai_declaration       :text
#  deleted_at           :datetime
#  demo_url             :text
#  description          :text
#  devlogs_count        :integer          default(0), not null
#  duration_seconds     :integer          default(0), not null
#  marked_fire_at       :datetime
#  memberships_count    :integer          default(0), not null
#  project_categories   :string           default([]), is an Array
#  project_type         :string
#  readme_url           :text
#  repo_url             :text
#  shadow_banned        :boolean          default(FALSE), not null
#  shadow_banned_at     :datetime
#  shadow_banned_reason :text
#  ship_status          :string           default("draft")
#  shipped_at           :datetime
#  synced_at            :datetime
#  title                :string           not null
#  tutorial             :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  fire_letter_id       :string
#  marked_fire_by_id    :bigint
#
# Indexes
#
#  index_projects_on_deleted_at         (deleted_at)
#  index_projects_on_marked_fire_by_id  (marked_fire_by_id)
#  index_projects_on_shadow_banned      (shadow_banned)
#
# Foreign Keys
#
#  fk_rails_...  (marked_fire_by_id => users.id)
#
class Project < ApplicationRecord
  include AASM
  include SoftDeletable

  has_ferret_search :title, :description

  SPACE_THEMED_PREFIX = "Space Themed:".freeze

  has_paper_trail

  has_many :sidequest_entries, dependent: :destroy
  has_many :sidequests, through: :sidequest_entries

  after_create :notify_slack_channel

  ACCEPTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  MAX_BANNER_SIZE = 10.megabytes

  AVAILABLE_CATEGORIES = [
    "CLI", "Cargo", "Web App", "Chat Bot", "Extension",
    "Desktop App (Windows)", "Desktop App (Linux)", "Desktop App (macOS)",
    "Minecraft Mods", "Hardware", "Android App", "iOS App", "Other"
  ].freeze

  scope :excluding_member, ->(user) {
    user ? where.not(id: user.projects) : all
  }
  scope :fire, -> { where.not(marked_fire_at: nil) }
  scope :with_banner_priority, -> {
    left_joins(:banner_attachment)
      .includes(banner_attachment: :blob)
      .order(ActiveStorage::Attachment.arel_table[:id].eq(nil).asc)
  }
  scope :excluding_shadow_banned, -> { where(shadow_banned: false) }
  scope :visible_to, ->(viewer) {
    if viewer&.shadow_banned?
      # Shadow-banned users see all projects (so they don't know they're banned)
      all
    elsif viewer
      # Regular users see non-shadow-banned projects + their own projects
      left_joins(memberships: :user)
        .where(shadow_banned: false)
        .where(memberships: { users: { shadow_banned: false } })
        .or(left_joins(memberships: :user).where(memberships: { user_id: viewer.id }))
        .distinct
    else
      excluding_shadow_banned
    end
  }

  belongs_to :marked_fire_by, class_name: "User", optional: true

  has_many :memberships, class_name: "Project::Membership", dependent: :destroy
  has_many :users, through: :memberships
  has_many :hackatime_projects, class_name: "User::HackatimeProject", dependent: :nullify
  has_many :posts, dependent: :destroy
  has_many :devlog_posts, -> { where(postable_type: "Post::Devlog").order(created_at: :desc) }, class_name: "Post"
  has_many :devlogs, through: :devlog_posts, source: :postable, source_type: "Post::Devlog"
  has_many :ship_event_posts, -> { where(postable_type: "Post::ShipEvent").order(created_at: :desc) }, class_name: "Post"
  has_many :ship_events, through: :ship_event_posts, source: :postable, source_type: "Post::ShipEvent"
  has_many :git_commit_posts, -> { where(postable_type: "Post::GitCommit").order(created_at: :desc) }, class_name: "Post"
  has_many :votes, dependent: :destroy
  has_many :reports, class_name: "Project::Report", dependent: :destroy
  has_many :skips, class_name: "Project::Skip", dependent: :destroy
  has_many :project_follows, dependent: :destroy
  has_many :followers, through: :project_follows, source: :user
  # needs to be implemented
  has_one_attached :demo_video

  # https://github.com/rails/rails/pull/39135
  has_one_attached :banner do |attachable|
    # using resize_to_limit to preserve aspect ratio without cropping
    # we're preprocessing them because its likely going to be used

    # for explore and projects#index
    attachable.variant :card,
                       resize_to_limit: [ 1600, 900 ],
                       format: :webp,
                       preprocessed: true,
                       saver: { strip: true, quality: 75 }

    #   attachable.variant :not_sure,
    #     resize_to_limit: [ 1200, 630 ],
    #     format: :webp,
    #     saver: { strip: true, quality: 75 }

    # for voting
    attachable.variant :thumb,
                       resize_to_limit: [ 400, 210 ],
                       format: :webp,
                       preprocessed: true,
                       saver: { strip: true, quality: 75 }
  end

  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 1_000 }, allow_blank: true
  validates :ai_declaration, length: { maximum: 1_000 }, allow_blank: true
  validates :demo_url, :repo_url, :readme_url,
            length: { maximum: 2_048 },
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) },
            allow_blank: true
  validates :banner,
            content_type: { in: ACCEPTED_CONTENT_TYPES, spoofing_protection: true },
            size: { less_than: MAX_BANNER_SIZE, message: "is too large (max 10 MB)" },
            processable_file: true
  validate :validate_project_categories

  def validate_project_categories
    return if project_categories.blank?

    invalid_types = project_categories - AVAILABLE_CATEGORIES
    if invalid_types.any?
      errors.add(:project_categories, "contains invalid types: #{invalid_types.join(', ')}")
    end
  end

  def validate_repo_cloneable
    return false if repo_url.blank?

    GitRepoService.is_cloneable? repo_url
  end

  def validate_repo_url_format
    return true if repo_url.blank?

    # Check if repo_url ends with .git or contains /tree/main
    repo_url.strip!
    if repo_url.end_with?(".git") || repo_url.include?("/tree/main")
      errors.add(:repo_url, "should not end with .git or contain /tree/main. Please use the root GitHub repository URL.")
      return false
    end
    true
  end

  def calculate_duration_seconds
    posts.of_devlogs(join: true).where(post_devlogs: { deleted_at: nil }).sum("post_devlogs.duration_seconds")
  end

  def recalculate_duration_seconds!
    update_column(:duration_seconds, calculate_duration_seconds)
  end

  # this can probaby be better?
  def soft_delete!(force: false)
    if !force && shipped?
      errors.add(:base, "Cannot delete a project that has been shipped")
      raise ActiveRecord::RecordInvalid.new(self)
    end
    update!(deleted_at: Time.current)
  end

  def shipped?
    shipped_at.present? || !draft?
  end

  def restore!
    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  def space_themed?
    description.to_s.lstrip.start_with?(SPACE_THEMED_PREFIX)
  end

  def description_without_space_theme_prefix
    description.to_s.sub(/\A\s*#{Regexp.escape(SPACE_THEMED_PREFIX)}\s*/, "")
  end

  def display_description
    description_without_space_theme_prefix
  end

  def hackatime_keys
    hackatime_projects.pluck(:name)
  end

  def total_hackatime_hours
    return 0 if hackatime_projects.empty?

    hackatime_uid = memberships.owner.first&.user&.hackatime_identity&.uid
    return 0 unless hackatime_uid

    total_seconds = HackatimeService.fetch_total_seconds_for_projects(hackatime_uid, hackatime_keys)
    return 0 unless total_seconds

    (total_seconds / 3600.0).round(1)
  end

  aasm column: :ship_status do
    state :draft, initial: true
    state :submitted
    state :under_review
    state :approved
    state :rejected

    event :submit_for_review do
      transitions from: [ :draft, :submitted, :under_review, :approved, :rejected ], to: :submitted, guard: :shippable?
      after do
        self.shipped_at = Time.current
      end
    end

    event :start_review do
      transitions from: :submitted, to: :under_review
    end

    event :approve do
      transitions from: :under_review, to: :approved
    end

    event :reject do
      transitions from: :under_review, to: :rejected
    end
  end

  def shipping_requirements
    [
      {
        key: :not_shadow_banned,
        label: "Your project must not be flagged by moderation",
        fail_label: "Your project has been flagged by moderation and cannot be shipped!",
        tooltip: "Your project has been reviewed by moderation and is ineligible to ship. Contact support if you think this is a mistake.",
        passed: !shadow_banned?
      },
      {
        key: :demo_url,
        label: "Add a demo link so anyone can try your project",
        tooltip: "A live URL where anyone can try your project, e.g. a deployed web app or a video demo.",
        passed: demo_url.present?
      },
      {
        key: :repo_url,
        label: "Add a public GitHub URL with your source code",
        tooltip: "A link to your public GitHub repository so others can view your code.",
        passed: repo_url.present?
      },
      {
        key: :repo_url_format,
        label: "Use the root GitHub repository URL (no .git or /tree/main)",
        tooltip: "Use the base repository URL, e.g. https://github.com/user/repo, not https://github.com/user/repo.git or https://github.com/user/repo/tree/main.",
        passed: validate_repo_url_format
      },
      {
        key: :repo_cloneable,
        label: "Make your GitHub repo publicly cloneable",
        tooltip: "Your repository must be public so anyone can clone and run your project.",
        passed: validate_repo_cloneable
      },
      {
        key: :readme_url,
        label: "Add a README URL to your project",
        tooltip: "A link to your README file, e.g. the raw GitHub URL of your README.md.",
        passed: readme_url.present?
      },
      {
        key: :description,
        label: "Add a description for your project",
        tooltip: "A short summary of what your project does and what makes it interesting.",
        passed: description.present?
      },
      {
        key: :banner,
        label: "Upload a banner image for your project",
        tooltip: "A banner image (JPEG, PNG, or WebP, max 10MB) that represents your project on the explore page.",
        passed: banner.attached?
      },
      {
        key: :devlog,
        label: "Post at least one devlog since your last ship",
        tooltip: "You must have posted at least one devlog after your previous ship to show progress on this version.",
        passed: has_devlog_since_last_ship?
      },
      {
        key: :payout,
        label: "Your previous ship must have received a payout before you can ship again",
        fail_label: "Wait for your previous ship to get a payout before shipping again",
        tooltip: "Your last ship is still awaiting a payout. You can ship again once that payout has been processed.",
        passed: previous_ship_event_has_payout?
      },
      {
        key: :vote_balance,
        label: "Maintain a non-negative vote balance",
        fail_label: "Your vote balance is negative! Vote on other projects before shipping this one.",
        tooltip: "Your vote balance has gone negative from downvotes. Earn it back by getting upvotes on your projects.",
        passed: memberships.owner.first&.user&.vote_balance.to_i >= 0
      },
      {
        key: :project_isnt_rejected,
        label: "Your project must not have been rejected",
        fail_label: "Your project is rejected!",
        tooltip: "Your last ship was rejected during review. Address the feedback before shipping again.",
        passed: last_ship_event&.certification_status != "rejected"
      },
      {
        key: :project_has_more_then_10s,
        label: "Log more than 10 seconds of tracked time across your devlogs",
        fail_label: "This project doesn't have any time attached to it! (devlog some time, then try again)",
        tooltip: "Your devlogs must have actual tracked time attached. Make sure you're logging time via Hackatime.",
        passed: duration_seconds > 10
      }
      # { key: :ai_declaration, label: "Declare your AI usage for this project (write 'None' if you didn't use any)", passed: ai_declaration.present? }
    ]
      .map.with_index
      .sort_by { |pair| [ pair[0][:passed] ? 1 : 0, pair[1] ] }
      .map { |it| it[0] }
  end

  def visual_shipping_requirements
    # only those that have a label we could use right now
    shipping_requirements.select { |elem| !elem[:passed] || elem[:label] }
  end

  def shippable? = shipping_requirements.all? { |r| r[:passed] }

  def ship_blocking_errors = shipping_requirements.reject { |r| r[:passed] }.map { |r| r[:label] }

  def last_ship_event
    ship_events.first
  end

  def has_legacy_ship_events?
    ship_events.where(voting_scale_version: Post::ShipEvent::LEGACY_VOTING_SCALE_VERSION).exists?
  end

  def has_paid_current_scale_ship_events?(excluding_ship_event_id: nil)
    scope = ship_events
              .where(voting_scale_version: Post::ShipEvent::CURRENT_VOTING_SCALE_VERSION)
              .where.not(payout: nil)
    scope = scope.where.not(id: excluding_ship_event_id) if excluding_ship_event_id.present?
    scope.exists?
  end

  def legacy_payout_total
    ship_events
      .where(voting_scale_version: Post::ShipEvent::LEGACY_VOTING_SCALE_VERSION)
      .where.not(payout: nil)
      .sum(:payout)
      .to_f
  end

  def total_ship_hours
    ship_events.sum(&:hours).to_f
  end

  def fire?
    marked_fire_at.present?
  end

  def mark_fire!(user)
    update!(marked_fire_at: Time.current, marked_fire_by: user)
  end

  def unmark_fire!
    update!(marked_fire_at: nil, marked_fire_by: nil)
  end

  def shadow_ban!(reason: nil)
    update!(shadow_banned: true, shadow_banned_at: Time.current, shadow_banned_reason: reason)
  end

  def unshadow_ban!
    update!(shadow_banned: false, shadow_banned_at: nil, shadow_banned_reason: nil)
  end

  def readme_is_raw_github_url?
    return false if readme_url.blank?

    begin
      uri = URI.parse(readme_url)
    rescue URI::InvalidURIError
      return false
    end

    return false unless uri.host == "raw.githubusercontent.com"

    /https:\/\/raw\.githubusercontent\.com\/[^\/]+\/[^\/]+\/[^\/]+\/.*README.*\.md/i.match?(uri.to_s)
  end

  private

  def has_devlog_since_last_ship?
    return true if last_ship_event.nil?
    devlog_posts.where("posts.created_at > ?", last_ship_event.created_at).exists?
  end

  def previous_ship_event_has_payout?
    return true if last_ship_event.nil?
    last_ship_event.payout.present?
  end

  def notify_slack_channel
    PostCreationToSlackJob.perform_later(self)
  end
end
