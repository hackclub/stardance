# == Schema Information
#
# Table name: projects
#
#  id                 :bigint           not null, primary key
#  ai_declaration     :text
#  deleted_at         :datetime
#  demo_url           :text
#  description        :text
#  devlogs_count      :integer          default(0), not null
#  duration_seconds   :integer          default(0), not null
#  marked_fire_at     :datetime
#  memberships_count  :integer          default(0), not null
#  project_categories :string           default([]), is an Array
#  project_type       :string
#  readme_url         :text
#  repo_url           :text
#  ship_status        :string           default("draft")
#  shipped_at         :datetime
#  synced_at          :datetime
#  title              :string           not null
#  tutorial           :boolean          default(FALSE), not null
#  update_description :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  fire_letter_id     :string
#  marked_fire_by_id  :bigint
#
# Indexes
#
#  index_projects_on_deleted_at         (deleted_at)
#  index_projects_on_marked_fire_by_id  (marked_fire_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (marked_fire_by_id => users.id)
#
require "net/http"

class Project < ApplicationRecord
  include AASM
  include SoftDeletable
  include SemanticSearchIndexable
  include Gorse::SyncableProject

  has_ferret_search :title, :description
  semantic_search_indexable type: "project"

  has_paper_trail

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
  scope :with_ship_events, -> { joins(:ship_events).distinct }
  scope :with_ship_events_between, ->(start_date, end_date) {
    joins(:posts)
      .where(posts: {
        postable_type: "Post::ShipEvent",
        created_at: start_date.beginning_of_day..end_date.end_of_day
      })
      .distinct
  }
  scope :with_banner_priority, -> {
    left_joins(:banner_attachment)
      .includes(banner_attachment: :blob)
      .order(ActiveStorage::Attachment.arel_table[:id].eq(nil).asc)
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
  has_many :ship_reviews, class_name: "Certification::Ship", dependent: :restrict_with_exception
  has_many :skips, class_name: "Project::Skip", dependent: :destroy
  has_many :project_follows, dependent: :destroy
  has_many :followers, through: :project_follows, source: :user

  has_many :mission_attachments,      class_name: "Project::MissionAttachment",  dependent: :destroy, inverse_of: :project
  has_many :missions,                 through:    :mission_attachments
  has_many :mission_section_completions, class_name: "Mission::SectionCompletion",  dependent: :destroy
  has_many :mission_submissions,         class_name: "Mission::Submission",         through: :ship_events

  def current_mission_attachment
    mission_attachments.where(detached_at: nil).order(attached_at: :desc).first
  end

  def current_mission
    current_mission_attachment&.mission
  end

  # True once this project has shipped to the given mission at least once.
  # After that first ship the mission stays attached (for display) but future
  # ships are regular, non-mission ships.
  def shipped_to_mission?(mission)
    return false if mission.nil?
    mission_submissions.where(mission_id: mission.id).exists?
  end

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

  def display_description
    description.to_s
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

  def seconds_coded_in_devlog_window(hackatime_uid, at: Time.current)
    HackatimeService.fetch_total_seconds_for_projects(
      hackatime_uid,
      hackatime_keys,
      start_date: devlog_window_start(at).iso8601,
      end_date: at.iso8601
    )
  end

  aasm column: :ship_status do
    state :draft, initial: true
    state :submitted
    state :under_review
    state :needs_changes
    state :approved
    state :rejected

    event :submit_for_review do
      transitions from: [ :draft, :submitted, :under_review, :needs_changes, :approved, :rejected ], to: :submitted, guard: :shippable?
      after do
        self.shipped_at = Time.current # I moved this logic to the ships controller as there's differences in how we handle reships - @AVD
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

    event :return_for_changes do
      transitions from: :under_review, to: :needs_changes
    end
  end

  # Maps each editable info field on the project form to the shipping
  # requirement keys it satisfies. Mirrors FIELD_REQUIREMENT_MAP in the
  # project-form Stimulus controller. The union of these keys is what
  # distinguishes "project info" from gates like devlog / payout / vote balance.
  FIELD_REQUIREMENT_MAP = {
    description: %i[description],
    demo_url: %i[demo_url demo_url_reachable],
    repo_url: %i[repo_url repo_url_format repo_cloneable],
    readme_url: %i[readme_url readme_url_reachable],
    banner: %i[banner]
  }.freeze

  INFO_REQUIREMENT_KEYS = FIELD_REQUIREMENT_MAP.values.flatten.freeze

  def shipping_requirements
    owner_vote_balance = memberships.owner.first&.user&.vote_balance.to_i
    votes_needed = [ -owner_vote_balance, 0 ].max
    [
      {
        key: :demo_url,
        label: "Add a demo link so anyone can try your project",
        tooltip: "A live URL where anyone can try your project, e.g. a deployed web app or a video demo.",
        passed: demo_url.present?
      },
      {
        key: :demo_url_reachable,
        label: "Your demo link must be reachable (not returning a 404 or error)",
        tooltip: "We checked your demo URL and it returned an error. Make sure it's publicly accessible.",
        passed: demo_url.blank? || url_reachable?(demo_url)
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
        key: :readme_url_reachable,
        label: "Your README URL must be reachable",
        tooltip: "We checked your README URL and it returned an error. Make sure it's a valid, publicly accessible link.",
        passed: readme_url.blank? || url_reachable?(readme_url)
      },
      {
        key: :description,
        label: "Add a description for your project",
        tooltip: "A short summary of what your project does and what makes it interesting.",
        passed: description.present?
      },
      {
        key: :banner,
        label: "Upload a screenshot of your project",
        tooltip: "A screenshot (JPEG, PNG, or WebP, max 10MB) that represents your project on the explore page.",
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
        fail_label: "Vote at least #{votes_needed} #{'time'.pluralize(votes_needed)} before shipping!",
        tooltip: "Your vote balance has gone negative from downvotes. Earn it back by getting upvotes on your projects.",
        passed: owner_vote_balance >= 0
      },
      {
        key: :idv,
        label: "Verify your identity",
        fail_label: "Verify your identity before shipping",
        tooltip: "Stardance needs to verify your identity through Hack Club Auth before you can ship — it keeps the program safe and is how we know where to send prizes.",
        passed: memberships.owner.first&.user&.identity_verified?
      },
      {
        key: :ysws_eligible,
        label: "You're eligible for YSWS prizes",
        fail_label: "You're not eligible for YSWS prizes yet — check the Hack Club portal",
        tooltip: "Your identity is verified, but YSWS eligibility is still pending. Open the Hack Club portal for details.",
        passed: memberships.owner.first&.user&.ysws_eligible?
      },
      {
        key: :shop_tutorial,
        label: "Pick stickers or nothing in the shop once",
        fail_label: "Visit the shop and pick stickers (or nothing) to get started",
        tooltip: "Before your first ship, go to the shop and pick either stickers or nothing. It shows you how the order flow works so a real order down the line doesn't catch you off guard.",
        passed: memberships.owner.first&.user&.shop_tutorial_completed?
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

  def shippable? = ship_blocking_errors.empty?

  def ship_blocking_errors = shipping_requirements.reject { |r| r[:passed] }.map { |r| r[:label] }

  # The single most relevant reason the project can't ship yet, as a short
  # actionable message — used for the ship button's disabled tooltip. Returns
  # nil when the project is shippable.
  def ship_blocker_message
    req = shipping_requirements.find { |r| !r[:passed] }
    req && (req[:fail_label] || req[:label])
  end

  # Whether every project-info requirement (see INFO_REQUIREMENT_KEYS) passes,
  # i.e. the editable details are filled in and ship-ready.
  def info_complete?
    shipping_requirements
      .select { |r| INFO_REQUIREMENT_KEYS.include?(r[:key]) }
      .all? { |r| r[:passed] }
  end

  def info_blocker_message
    req = shipping_requirements
      .select { |r| INFO_REQUIREMENT_KEYS.include?(r[:key]) }
      .find { |r| !r[:passed] }
    req&.dig(:label)
  end

  # The editable info fields (see FIELD_REQUIREMENT_MAP) that still have an
  # unmet requirement — used to highlight what's left to fill in on the form.
  def incomplete_info_fields
    unmet = shipping_requirements.reject { |r| r[:passed] }.map { |r| r[:key] }
    FIELD_REQUIREMENT_MAP.select { |_field, keys| (keys & unmet).any? }.keys
  end

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

  def has_devlog_since_last_ship?
    scope = devlog_posts
    scope = scope.where("posts.created_at > ?", last_ship_event.created_at) if last_ship_event
    scope.exists?
  end

  # The recommended next action for this project is to post a devlog when the
  # user either hasn't posted anything yet or their most recent post was a
  # ship (i.e. progress is needed before the next ship).
  def next_step_is_devlog?
    last_devlog_at = devlog_posts.maximum(:created_at)
    return true if last_devlog_at.nil?

    last_ship_at = ship_event_posts.maximum(:created_at)
    last_ship_at.present? && last_ship_at > last_devlog_at
  end

  # Public so ProjectUrlProbeService can probe demo/repo URLs on re-ship. The
  # HTTP helpers it leans on stay private below.
  def url_reachable?(url)
    cache_key = "url_reachable_#{Digest::MD5.hexdigest(url)}"
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      response = SafeUrl.safe_head(url)
      response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
    end
  rescue SafeUrl::Error, URI::InvalidURIError, SocketError, Errno::ECONNREFUSED,
         Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
    false
  end

  private

  def devlog_window_start(at)
    previous_devlog = devlogs.where("post_devlogs.created_at < ?", at).order("post_devlogs.created_at desc").first
    previous_devlog&.created_at || [ created_at, Date.parse(HackatimeService::START_DATE).beginning_of_day ].min
  end

  def previous_ship_event_has_payout?
    return true if last_ship_event.nil?
    last_ship_event.payout.present?
  end

  def notify_slack_channel
    PostCreationToSlackJob.perform_later(self)
  end
end
