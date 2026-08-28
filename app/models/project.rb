# == Schema Information
#
# Table name: projects
#
#  id                   :bigint           not null, primary key
#  ai_declaration       :text
#  deleted_at           :datetime
#  demo_url             :text
#  description          :text
#  devlogs_count        :integer          default(0), not null
#  duration_seconds     :integer          default(0), not null
#  hardware_stage       :string
#  marked_fire_at       :datetime
#  memberships_count    :integer          default(0), not null
#  nominated_fire_at    :datetime
#  project_categories   :string           default([]), is an Array
#  project_type         :string
#  readme_url           :text
#  repo_url             :text
#  ship_status          :string           default("draft")
#  shipped_at           :datetime
#  synced_at            :datetime
#  title                :string           not null
#  tutorial             :boolean          default(FALSE), not null
#  update_description   :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  fire_letter_id       :string
#  marked_fire_by_id    :bigint
#  nominated_fire_by_id :bigint
#
# Indexes
#
#  index_projects_on_deleted_at            (deleted_at)
#  index_projects_on_marked_fire_by_id     (marked_fire_by_id)
#  index_projects_on_nominated_fire_by_id  (nominated_fire_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (marked_fire_by_id => users.id)
#  fk_rails_...  (nominated_fire_by_id => users.id)
#
require "net/http"

class Project < ApplicationRecord
  include Project::HackatimeDevlogResync
  include AASM
  include SoftDeletable
  include SemanticSearchIndexable
  include Gorse::SyncableProject

  has_ferret_search :title, :description
  semantic_search_indexable type: "project"

  has_paper_trail

  after_create :notify_slack_channel
  after_commit :ensure_hackatime_projects, if: :needs_hackatime_project?

  ACCEPTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  MAX_BANNER_SIZE = 10.megabytes

  AVAILABLE_CATEGORIES = [
    "CLI", "Cargo", "Web App", "Chat Bot", "Extension",
    "Desktop App (Windows)", "Desktop App (Linux)", "Desktop App (macOS)",
    "Minecraft Mods", "Hardware", "Android App", "iOS App", "Other"
  ].freeze
  USER_SELECTABLE_TYPES = (AVAILABLE_CATEGORIES - [ "Hardware" ]).freeze

  # Titles the create flows post before the builder has named anything: the
  # /projects/new hidden field submits "Untitled" and the setup wizard starts at
  # "Untitled project". A project usually turns hardware while still carrying one
  # of these, so anything keyed on the title has to wait for a real one.
  DEFAULT_TITLE = "Untitled".freeze
  SETUP_DEFAULT_TITLE = "Untitled project".freeze
  PLACEHOLDER_TITLES = [ DEFAULT_TITLE, SETUP_DEFAULT_TITLE ].freeze
  TITLE_MAX_LENGTH = 120

  # Hardware projects carry a build/design stage; software projects leave
  # hardware_stage nil. Hardware builders can't run a Hackatime editor plugin, so
  # they record Lapse timelapses against a seeded Hackatime project instead.
  HARDWARE_STAGES = %w[design build].freeze

  scope :excluding_member, ->(user) {
    user ? where.not(id: user.projects) : all
  }
  scope :hardware, -> { where.not(hardware_stage: nil) }
  # A hardware mission reviews its own attached projects on the mission dash, so
  # the global hardware queue leaves them out. The two scopes are exact
  # complements, which is what keeps every hardware review counted once.
  scope :with_hardware_mission, -> { where(id: hardware_mission_project_ids) }
  scope :without_hardware_mission, -> { where.not(id: hardware_mission_project_ids) }

  def self.hardware_mission_project_ids
    Project::MissionAttachment.active.joins(:mission).where(missions: { hardware: true }).select(:project_id)
  end
  # Projects with no Hackatime project linked for this member yet. Scoped per
  # member rather than per project: on a shared project each member records
  # their own Lapse time, so one member's link doesn't cover anyone else.
  #
  # The subquery has to drop nil project_ids. A NULL inside NOT IN makes the
  # whole predicate unknown, and the scope would match nothing at all.
  scope :without_hackatime_project_for, ->(user) {
    where.not(id: User::HackatimeProject.where(user: user).where.not(project_id: nil).select(:project_id))
  }
  scope :fire, -> { where.not(marked_fire_at: nil) }
  scope :fire_nomination_pending, -> { where.not(nominated_fire_at: nil).where(marked_fire_at: nil) }
  scope :with_ship_events, -> { joins(:ship_events).distinct }
  scope :with_ship_events_between, ->(start_date, end_date) {
    joins(:posts)
      .where(posts: {
        postable_type: "Post::ShipEvent",
        created_at: start_date.beginning_of_day..end_date.end_of_day
      })
      .distinct
  }
  scope :needs_language_sync, -> {
    where.not(repo_url: [ nil, "" ])
      .left_joins(:project_language)
      .where(
        "project_languages.id IS NULL OR " \
        "project_languages.status IN (?) OR " \
        "(project_languages.status = ? AND project_languages.last_synced_at < ?)",
        [ ProjectLanguage.statuses[:pending], ProjectLanguage.statuses[:failed] ],
        ProjectLanguage.statuses[:synced],
        1.day.ago
      )
      .order(
        Arel.sql("CASE WHEN project_languages.id IS NULL THEN 0 ELSE 1 END"),
        Arel.sql("project_languages.last_synced_at ASC NULLS FIRST")
      )
  }
  scope :with_banner_priority, -> {
    left_joins(:banner_attachment)
      .includes(banner_attachment: :blob)
      .order(ActiveStorage::Attachment.arel_table[:id].eq(nil).asc)
  }
  belongs_to :marked_fire_by, class_name: "User", optional: true
  belongs_to :nominated_fire_by, class_name: "User", optional: true

  has_many :memberships, class_name: "Project::Membership", dependent: :destroy
  has_many :users, through: :memberships
  has_many :hackatime_projects, class_name: "User::HackatimeProject", dependent: :nullify
  has_many :lookout_sessions, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :devlog_posts, -> { where(postable_type: "Post::Devlog").order(created_at: :desc) }, class_name: "Post"
  has_many :devlogs, through: :devlog_posts, source: :postable, source_type: "Post::Devlog"
  has_many :ship_event_posts, -> { where(postable_type: "Post::ShipEvent").order(created_at: :desc) }, class_name: "Post"
  has_many :ship_events, through: :ship_event_posts, source: :postable, source_type: "Post::ShipEvent"
  has_many :git_commit_posts, -> { where(postable_type: "Post::GitCommit").order(created_at: :desc) }, class_name: "Post"
  has_many :votes, dependent: :destroy
  has_many :vote_events, class_name: "Vote::Event", dependent: :nullify
  has_many :reports, class_name: "Project::Report", dependent: :destroy
  has_many :ship_reviews, class_name: "Certification::Ship", dependent: :restrict_with_exception
  has_many :certification_funding_requests, class_name: "Certification::FundingRequest", dependent: :destroy
  has_many :review_notes, class_name: "Certification::ReviewNote", dependent: :destroy
  has_many :integrity_checks, through: :ship_events, source: :integrity_check
  has_many :skips, class_name: "Project::Skip", dependent: :destroy
  has_many :project_follows, dependent: :destroy
  has_many :followers, through: :project_follows, source: :user

  has_one :project_language, dependent: :destroy

  has_many :mission_attachments,      class_name: "Project::MissionAttachment",  dependent: :destroy, inverse_of: :project
  has_many :missions,                 through:    :mission_attachments
  has_many :mission_section_completions, class_name: "Mission::SectionCompletion",  dependent: :destroy
  has_many :mission_submissions,         class_name: "Mission::Submission",         through: :ship_events

  def current_mission_attachment
    if mission_attachments.loaded?
      mission_attachments.select { |ma| ma.detached_at.nil? }.max_by(&:attached_at)
    else
      mission_attachments.where(detached_at: nil).order(attached_at: :desc).first
    end
  end

  def current_mission
    current_mission_attachment&.mission
  end

  # The active mission delivers a physical kit at design approval (an
  # after_design prize) instead of a cash grant.
  def awards_design_kit?
    current_mission&.prizes&.after_design&.exists? || false
  end

  def display_banner
    if banner.attached?
      banner
    elsif current_mission&.banner&.attached?
      current_mission.banner
    end
  end

  # True once this project has shipped to the given mission at least once.
  # After that first ship the mission stays attached (for display) but future
  # ships are regular, non-mission ships.
  def shipped_to_mission?(mission)
    return false if mission.nil?
    mission_submissions.not_rejected.where(mission_id: mission.id).exists?
  end

  # The one exception to the shipped-projects-keep-their-mission rule: a
  # shipped project may still attach a mission that lists one it shipped to
  # as a direct prerequisite (e.g. webOS 1 -> webOS 2).
  def eligible_follow_up_mission?(mission)
    return false if mission.nil? || !mission.has_prerequisites?
    mission_submissions.not_rejected.where(mission_id: mission.prerequisite_ids).exists?
  end

  # Makes `mission` the current mission, replacing the active attachment
  # when the swap is allowed: draft projects switch freely, shipped projects
  # only move to a follow-up or back to a mission they shipped to. Otherwise
  # the attachment validations raise RecordInvalid.
  def attach_mission!(mission)
    with_lock do
      current = current_mission_attachment
      current.detach! if current && may_swap_mission_to?(mission)
      mission_attachments.create!(mission: mission, attached_at: Time.current)
    end
  end

  # Detaches the current mission and returns the fallback it re-attached,
  # if any — a shipped project never goes mission-less.
  def detach_mission!
    with_lock do
      attachment = current_mission_attachment
      next nil unless attachment

      attachment.detach!
      fallback = fallback_mission_after_detaching(attachment.mission)
      mission_attachments.create!(mission: fallback, attached_at: Time.current) if fallback
      fallback
    end
  end

  # The mission a detach falls back to: the most recent one this project
  # shipped to, other than the mission being detached.
  def fallback_mission_after_detaching(mission)
    scope = mission_submissions.not_rejected
    scope = scope.where.not(mission_id: mission.id) if mission
    scope.order(created_at: :desc).first&.mission
  end

  # Whether `mission` may replace the current attachment: draft projects
  # switch freely; shipped projects only move to a follow-up or back to a
  # mission they shipped to. The attachment validation enforces this too.
  def may_swap_mission_to?(mission)
    !shipped? || shipped_to_mission?(mission) || eligible_follow_up_mission?(mission)
  end

  # Follow-up missions for the switch UI, in one pass: :ready to attach now
  # (all prerequisites approved for the user), :awaiting this project's
  # in-review ships clearing (shown as disabled teasers).
  def follow_up_targets_for(user)
    targets = { ready: [], awaiting: [] }
    mission = current_mission
    return targets if user.nil? || mission.nil? || !shipped_to_mission?(mission)

    missions = mission.unlocks.available.includes(:prerequisites).to_a
    return targets if missions.empty?

    completed_ids = user.completed_mission_ids
    in_review_ids = mission_submissions.in_review.pluck(:mission_id)
    missions.each do |mission|
      missing = mission.prerequisite_ids - completed_ids
      if missing.empty?
        targets[:ready] << mission
      elsif (missing - in_review_ids).empty?
        targets[:awaiting] << mission
      end
    end
    targets
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

  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
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
  # A blank hardware_stage means "software project". The edit form's type
  # toggle submits an empty string when Software is selected; coerce it to nil
  # so the column actually clears and passes the inclusion validation (which
  # allows nil, but not "").
  normalizes :hardware_stage, with: ->(value) { value.presence }
  validates :hardware_stage, inclusion: { in: HARDWARE_STAGES }, allow_nil: true
  validates :project_type, inclusion: { in: AVAILABLE_CATEGORIES }, allow_nil: true
  validate :hardware_stage_locked_once_committed
  validate :hardware_required_by_current_mission

  # Set by Certification::FundingRequest#apply_verdict_to_project! to let the
  # approval flow advance the stage; the lock below stays closed for everyone else.
  attr_accessor :advancing_via_funding_approval

  # Set when a builder confirms a reviewer's "wrong queue" flag. The submission
  # that locked the stage is being rolled back, so the lock has to open for the
  # correction - see Certification::Reviewable#confirm_queue_conversion!.
  attr_accessor :converting_review_queue

  # Set when a reviewer undoes a decided hardware review and the funding approval
  # that moved the project design -> build is being reversed. The lock has to
  # open for the rewind - see Certification::ReviewUndoer.
  attr_accessor :reverting_hardware_review

  # Once a project has asked for funding or shipped, its stage decides real
  # money: hardware pays a flat rate and skips the payout review window, so an
  # owner must not be able to flip an already-shipped software project to
  # hardware and change how it gets paid.
  def hardware_stage_locked_once_committed
    return unless hardware_stage_changed?
    return if advancing_via_funding_approval || converting_review_queue || reverting_hardware_review

    if has_any_funding_request?
      errors.add(:hardware_stage, "cannot be changed after a funding request has been submitted")
    elsif shipped_at_least_once?
      errors.add(:hardware_stage, "cannot be changed after the project has shipped")
    end
  end

  # Deliberately not memoized: a Project instance can be validated before a ship
  # exists and again after (reload doesn't clear an ivar), and a stale false here
  # would let the stage change through.
  def shipped_at_least_once?
    ship_events.exists?
  end

  # The edit form asks this so it can render a locked display instead of a
  # control that would only fail validation.
  def hardware_stage_locked?
    has_any_funding_request? || shipped_at_least_once?
  end

  # A project on a hardware mission can't drop back to software while attached —
  # the mission only accepts hardware projects (Mission#hardware?). Detach first.
  # Only queries the mission when the project is actually leaving hardware.
  def hardware_required_by_current_mission
    return unless hardware_stage_changed? && !hardware?
    return unless current_mission&.hardware?

    errors.add(:hardware_stage, "can't be software while attached to the #{current_mission.name} hardware mission")
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

    transaction do
      now = Time.current
      update!(deleted_at: now)

      hackatime_projects.update_all(project_id: nil, updated_at: now) unless shipped?

      devlogs.find_each { |d| d.update_columns(deleted_at: now) }

      Post::Repost.unscoped.where(original_post_id: posts.pluck(:id)).find_each do |repost|
        repost.update_columns(deleted_at: now)
      end
    end
  end

  def restore!
    transaction do
      deleted_at_was = deleted_at
      update!(deleted_at: nil)

      Post::Devlog.unscoped.where(deleted_at: deleted_at_was)
                  .where(id: posts.of_devlogs.pluck(:postable_id))
                  .update_all(deleted_at: nil)

      repost_ids = Post::Repost.unscoped.where(deleted_at: deleted_at_was)
                               .where(original_post_id: posts.pluck(:id))
                               .pluck(:id)

      Post::Repost.unscoped.where(id: repost_ids).update_all(deleted_at: nil)
    end
  end

  def shipped?
    shipped_at.present? || !draft?
  end

  def hardware?
    hardware_stage.present?
  end

  # The moment a project turns hardware, whether it was born that way or was
  # switched over later. Design → build doesn't count: the project is already
  # hardware and its Hackatime project already exists.
  def became_hardware?
    saved_change_to_hardware_stage? && hardware? && hardware_stage_before_last_save.blank?
  end

  # Still carrying a name the create flow filled in, rather than one the builder
  # chose. The Hackatime project is named after the title, so seeding one now
  # would leave the builder recording Lapse timelapses against "Untitled".
  def placeholder_title?
    title.blank? || PLACEHOLDER_TITLES.include?(title.strip)
  end

  # Seed when a hardware project first has a name worth using: either it just
  # turned hardware and is already named, or it just got renamed. Projects are
  # normally created placeholder-named and turn hardware before the builder
  # names them, so the rename is usually the trigger that matters.
  def needs_hackatime_project?
    return false unless hardware? && !placeholder_title?

    became_hardware? || saved_change_to_title?
  end

  def design_stage?
    hardware_stage == "design"
  end

  def build_stage?
    hardware_stage == "build"
  end

  # Rolls the review state back when a ship is withdrawn. Without this the
  # project keeps `ship_status: submitted` and a `shipped_at`, so `shipped?`
  # stays true forever: no mission can be attached, deletion needs force, and
  # the page keeps treating it as already shipped. Skipped when an earlier real
  # ship still stands, since that ship's outcome is the state to keep.
  def roll_back_withdrawn_ship!
    return if last_ship_event
    return unless may_withdraw_ship?

    withdraw_ship!
  end

  # The submission a reviewer flagged as being in the wrong hardware queue and
  # the builder hasn't answered yet. Only one can exist at a time: flagging
  # takes the submission out of its queue, and nothing new can be submitted
  # until the question is answered.
  def review_awaiting_queue_answer
    certification_funding_requests.misfiled.order(created_at: :desc).first ||
      ship_reviews.misfiled.order(created_at: :desc).first
  end

  # True while a funding request for this project is awaiting reviewer decision.
  def has_pending_funding_request?
    certification_funding_requests.pending.exists?
  end

  # True once any funding request has been submitted (pending, approved, or returned).
  def has_any_funding_request?
    return @_has_any_funding_request if defined?(@_has_any_funding_request)
    @_has_any_funding_request = certification_funding_requests.exists?
  end

  # The latest funding request (for displaying approved amount, status, etc.).
  def latest_funding_request
    return @_latest_funding_request if defined?(@_latest_funding_request)
    @_latest_funding_request = certification_funding_requests.order(created_at: :desc, id: :desc).first
  end

  # The review the action-item gate answers to. Views and controllers have to
  # agree on which record this is or a builder can be shown one checklist and
  # judged against another, so there is one definition.
  def latest_ship_review
    return @_latest_ship_review if defined?(@_latest_ship_review)
    @_latest_ship_review = ship_reviews.order(created_at: :desc, id: :desc).first
  end

  # with_lock (and any explicit reload) refreshes the row but leaves these
  # request-scoped memos in place, so a value read before the lock would leak a
  # pre-lock snapshot into the locked section. Drop them whenever the record
  # reloads. remove_instance_variable, not nil: the memos guard on `defined?`.
  def reload(*)
    %i[@_latest_ship_review @_latest_funding_request @_has_any_funding_request].each do |ivar|
      remove_instance_variable(ivar) if instance_variable_defined?(ivar)
    end
    super
  end

  # The open fraud flag on this project, if any. The hardware review page derives
  # its "flagged for fraud" state from this rather than a dedicated column.
  def pending_fraud_report
    reports.pending.where(reason: "fraud").order(created_at: :desc).first
  end

  # Funding reviews to interleave into the project timeline: every request the
  # owner has a standing outcome for - pending (awaiting a verdict), approved,
  # or returned. Showing all of them, rather than only the latest, lets an older
  # returned review keep its chronological place in the feed (see
  # +timeline_sort_key+) and scroll down as newer devlogs land above it.
  # Misfiled requests are surfaced by the queue-mismatch card instead, and
  # withdrawn ones carry no verdict, so both stay off the feed.
  def timeline_funding_requests
    certification_funding_requests
      .where(status: [ :pending, :approved, :returned ])
      .order(created_at: :desc)
  end

  # Orders a project's timeline entries (devlog posts, ship decisions, and
  # funding reviews) newest-first for the project feed.
  def self.sort_timeline_entries(entries)
    entries.sort_by { |entry| timeline_sort_key(entry) }.reverse
  end

  # Where a timeline entry sits in the feed: a review at the moment it was
  # decided, everything else at its creation. Falling back to +created_at+ keeps
  # a still-pending review at the point it was submitted.
  def self.timeline_sort_key(entry)
    case entry
    when Certification::Ship then entry.decided_on
    when Certification::FundingRequest then entry.decided_at || entry.created_at
    else entry.created_at
    end
  end

  # Name of the Hackatime project this project's time is filed under (and which
  # Project::EnsureHackatimeProjectsJob seeds for hardware builders to pick in
  # Lapse): the project title, so timelapse time lands under the same Hackatime
  # project as any code-based time.
  def hackatime_recorder_name
    title
  end

  def display_description
    description.to_s
  end


  # Deduplicated because every member of a hardware project gets their own
  # User::HackatimeProject row under the same name, and callers treat this as a
  # set: it's joined into the Airtable sync and the devlog key snapshot, and
  # rendered as-is on the integrity dashboard.
  def hackatime_keys
    hackatime_projects.distinct.pluck(:name)
  end

  def total_hackatime_hours
    return 0 if hackatime_projects.empty?

    hackatime_uid = memberships.owner.first&.user&.hackatime_identity&.uid
    return 0 unless hackatime_uid

    total_seconds = HackatimeService.fetch_total_seconds_for_projects(hackatime_uid, hackatime_keys, access_token: memberships.owner.first&.user&.hackatime_identity&.access_token)
    return 0 unless total_seconds

    (total_seconds / 3600.0).round(1)
  end

  def seconds_coded_in_devlog_window(hackatime_uid, at: Time.current, access_token: nil)
    HackatimeService.fetch_total_seconds_for_projects(
      hackatime_uid,
      hackatime_keys,
      start_date: devlog_window_start(at).iso8601,
      end_date: at.iso8601,
      access_token: access_token
    )
  end

  # Where the current devlog window opened: the previous devlog, or for the
  # first devlog the earlier of project creation and season start.
  def devlog_window_start(at)
    previous_devlog = devlogs.where("post_devlogs.created_at < ?", at).order("post_devlogs.created_at desc").first
    previous_devlog&.created_at || [ created_at, Date.parse(HackatimeService::START_DATE).beginning_of_day ].min
  end

  aasm column: :ship_status do
    state :draft, initial: true
    state :submitted
    state :under_review
    state :needs_changes
    state :approved
    state :rejected

    event :submit_for_review do
      transitions from: [ :draft, :submitted, :under_review, :needs_changes, :approved, :rejected ],
                  to: :submitted,
                  guard: :shippable?,
                  after: -> { self.shipped_at = Time.current }
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
      transitions from: [ :under_review, :approved ], to: :needs_changes
    end

    event :resubmit_for_review do
      transitions from: :needs_changes, to: :submitted
    end

    # A ship that was withdrawn rather than judged (see
    # Certification::Reviewable#confirm_queue_conversion!). Clears shipped_at
    # too, since `shipped?` reads either one.
    event :withdraw_ship do
      transitions from: [ :submitted, :under_review ], to: :draft,
                  after: -> { self.shipped_at = nil }
    end
  end

  # Maps each editable info field on the project form to the shipping
  # requirement keys it satisfies. The union of these keys is what
  # distinguishes "project info" from gates like devlog / payout / vote balance.
  FIELD_REQUIREMENT_MAP = {
    description: %i[description],
    demo_url: %i[demo_url demo_url_reachable],
    repo_url: %i[repo_url repo_url_format repo_cloneable],
    readme_url: %i[readme_url readme_url_reachable],
    banner: %i[banner],
    ai_declaration: %i[ai_declaration]
  }.freeze

  INFO_REQUIREMENT_KEYS = FIELD_REQUIREMENT_MAP.values.flatten.freeze

  # The subset of project info required to submit a design-stage funding request.
  # A demo link usually doesn't exist yet while the build is still being
  # designed, so demo_url is dropped from the funding gate. It stays in
  # INFO_REQUIREMENT_KEYS, so it's still required to ship.
  FUNDING_INFO_REQUIREMENT_KEYS = (INFO_REQUIREMENT_KEYS - FIELD_REQUIREMENT_MAP[:demo_url]).freeze

  def shipping_requirements
    owner_vote_balance = memberships.owner.first&.user&.vote_balance.to_i
    votes_needed = [ -owner_vote_balance, 0 ].max
    mission_review = blocking_mission_submission
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
        key: :ai_declaration,
        label: "Declare your AI usage (write \"None\" if you didn't use any)",
        tooltip: "Describe how you used AI in this project. AI use is OK, but it should feel like your own work — if you didn't use any, write \"None\".",
        passed: ai_declaration.present?
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
        key: :build_devlog,
        label: "Post at least one build devlog before shipping",
        fail_label: "Post at least one build devlog before you can ship!",
        tooltip: "Now that your project is funded it's in the build stage. Log some build time and post a build devlog to show progress before you ship. Design-stage devlogs don't count.",
        passed: !received_grant? || has_build_devlog_since_last_ship?
      },
      {
        key: :payout,
        label: "Your previous ship must have received a payout before you can ship again",
        fail_label: "Wait for your previous ship to get a payout before shipping again",
        tooltip: "Your last ship is still awaiting a payout. You can ship again once that payout has been processed.",
        passed: previous_ship_event_has_payout?
      },
      {
        key: :mission_review,
        label: "Your mission submission must clear review before you ship again",
        fail_label: mission_review&.rejected? ?
          "Your mission submission was returned. Address the feedback and request a re-review" :
          "Wait for your mission submission to be reviewed before shipping again",
        tooltip: mission_review&.rejected? ?
          "A reviewer returned your mission submission. Address their feedback and request a re-review from the ship on your timeline, or detach the mission to carry on without it." :
          "Your ship is waiting on a mission reviewer. You can ship again once they've made a decision.",
        passed: mission_review.nil?
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
    ]
      .map.with_index
      .sort_by { |pair| [ pair[0][:passed] ? 1 : 0, pair[1] ] }
      .map { |it| it[0] }
  end

  def shippable? = ship_blocking_errors.empty?

  # True while a ship is waiting on a reviewer decision. Blocks re-shipping
  # until that ship is approved or returned for changes.
  def awaiting_ship_review? = ship_reviews.pending.exists?

  def ship_blocking_errors = shipping_requirements.reject { |r| r[:passed] }.map { |r| r[:label] }

  # The latest ship's mission submission while it still owes a decision:
  # `pending` waits on a reviewer, `rejected` waits on the builder to address
  # the feedback and request a re-review. Either way the project can't ship
  # again. A ship the certifier rejected is left to the re-certification flow.
  def blocking_mission_submission
    ship = last_ship_event
    return nil if ship.nil? || ship.certification_status == "rejected"

    submission = ship.mission_submission
    submission if submission&.pending? || submission&.rejected?
  end

  # The single most relevant reason the project can't ship yet, as a short
  # actionable message — used for the ship button's disabled tooltip. Returns
  # nil when the project is shippable.
  def ship_blocker_message
    req = shipping_requirements.find { |r| !r[:passed] }
    req && (req[:fail_label] || req[:label])
  end

  # The mission-review blocker, when that's what's holding the ship button.
  # Takes precedence over the other blockers in the UI: nothing the builder
  # fixes on the project itself unblocks a review that hasn't landed yet.
  def mission_review_blocker_message
    req = shipping_requirements.find { |r| r[:key] == :mission_review }
    return nil if req[:passed]

    req[:fail_label] || req[:label]
  end

  # Whether every project-info requirement (see INFO_REQUIREMENT_KEYS) passes,
  # i.e. the editable details are filled in and ship-ready.
  def info_complete?
    info_requirements_met?(INFO_REQUIREMENT_KEYS)
  end

  # Whether the info needed to submit a design-stage funding request is complete.
  # Unlike #info_complete? this doesn't require a demo link, which usually
  # doesn't exist yet at the design stage (see FUNDING_INFO_REQUIREMENT_KEYS).
  def funding_info_complete?
    info_requirements_met?(FUNDING_INFO_REQUIREMENT_KEYS)
  end

  # Whether the project info needed for the current stage's next action is
  # complete. At the design stage the next action is a funding request, which
  # doesn't need a demo link (see #funding_info_complete?); once building, the
  # next action is shipping, which does (see #info_complete?).
  def stage_info_complete?
    design_stage? ? funding_info_complete? : info_complete?
  end

  # Label of the first unmet info requirement for the current stage, used as the
  # "Complete project info" tooltip. Mirrors #stage_info_complete? so a
  # design-stage builder is never nagged about a demo link they don't yet need.
  def info_blocker_message
    keys = design_stage? ? FUNDING_INFO_REQUIREMENT_KEYS : INFO_REQUIREMENT_KEYS
    req = shipping_requirements
      .select { |r| keys.include?(r[:key]) }
      .find { |r| !r[:passed] }
    req&.dig(:label)
  end

  # The editable info fields (see FIELD_REQUIREMENT_MAP) that still have an
  # unmet requirement for the current stage — used to highlight what's left to
  # fill in on the form. Stage-aware like #stage_info_complete?, so a demo link
  # isn't flagged red while designing (it isn't needed until shipping).
  def incomplete_info_fields
    stage_keys = design_stage? ? FUNDING_INFO_REQUIREMENT_KEYS : INFO_REQUIREMENT_KEYS
    unmet = shipping_requirements
      .select { |r| stage_keys.include?(r[:key]) }
      .reject { |r| r[:passed] }
      .map { |r| r[:key] }
    FIELD_REQUIREMENT_MAP.select { |_field, keys| (keys & unmet).any? }.keys
  end

  # A misfiled ship is being rolled back, not judged, so it must not count as
  # "the last ship" for the post-ship prerequisites - otherwise the builder
  # would have to post a fresh devlog before they could resubmit to the queue
  # the reviewer sent them to.
  def last_ship_event
    ship_events.where.not(certification_status: "misfiled").first
  end

  def total_ship_hours
    ship_events.sum(&:hours).to_f
  end

  def fire?
    marked_fire_at.present?
  end

  def fire_nomination_pending?
    nominated_fire_at.present? && marked_fire_at.nil?
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

  # True once this project has had a funding request approved (the "I need
  # Funding" path). Such projects must show real build progress before shipping.
  def received_grant?
    certification_funding_requests.approved.exists?
  end

  # The approved funding request that actually handed something over: a grant
  # card or a mission kit. An approval that waived both costs nothing to undo,
  # so it doesn't count. Warns a reviewer before they send a funded project back
  # to design, where it could be funded a second time.
  def delivered_funding_request
    certification_funding_requests.approved.find { |r| r.issues_grant? || r.awards_design_kit? }
  end

  # Re-files this project's design-phase devlogs as build time. Only ever used
  # when a builder confirms they never needed funding: they were logging build
  # work under a design-stage project, and an unfunded hardware builder is paid
  # for exactly that work from day one. Payout-affecting, so it is recorded in
  # PaperTrail like any other admin-side correction.
  def refile_design_devlogs_as_build!
    # validate: false because this only moves an existing devlog between phases:
    # re-running the composer's content validations (attachments in particular)
    # would let an old post block the correction. Callbacks and PaperTrail still
    # run, so the change stays auditable.
    devlogs.design_phase.find_each do |devlog|
      devlog.phase = "build"
      devlog.save!(validate: false)
    end
  end

  # Funded projects must post at least one BUILD-phase devlog since their last
  # ship before they can ship — design-phase devlogs (logged before the grant)
  # don't count.
  def has_build_devlog_since_last_ship?
    scope = devlogs.build_phase.where(deleted_at: nil)
    scope = scope.where("post_devlogs.created_at > ?", last_ship_event.created_at) if last_ship_event
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

  PROBE_SKIP_DOMAINS = %w[
    npmjs.com
    crates.io
    curseforge.com
    makerworld.com
    streamlit.app
  ].freeze

  # Public so ProjectUrlProbeService and the controller can probe URLs.
  # Returns the HTTP status code (int), nil for allowlisted domains.
  def url_probe_status(url, cache: true)
    uri = URI.parse(url)
    return nil if PROBE_SKIP_DOMAINS.any? { |d| uri.host&.end_with?(d) }

    if cache
      Rails.cache.fetch("url_probe_v2_#{Digest::MD5.hexdigest(url)}", expires_in: 5.minutes) do
        do_url_probe(url)
      end
    else
      do_url_probe(url)
    end
  end

  def url_reachable?(url)
    status = url_probe_status(url)
    status.nil? || (200..299).cover?(status)
  rescue SafeUrl::Error, URI::InvalidURIError, SocketError, Errno::ECONNREFUSED,
         Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
    false
  end

  private

  # Whether every shipping requirement in `keys` currently passes. Shared by
  # #info_complete? (all info keys) and #funding_info_complete? (info minus demo).
  def info_requirements_met?(keys)
    shipping_requirements
      .select { |r| keys.include?(r[:key]) }
      .all? { |r| r[:passed] }
  end

  def do_url_probe(url)
    response = SafeUrl.safe_get(
      url,
      headers: { "User-Agent" => "Stardance project validator (https://stardance.hackclub.com/)" },
      open_timeout: 5,
      read_timeout: 5
    )
    response.code.to_i
  end

  def previous_ship_event_has_payout?
    return true if last_ship_event.nil?
    return true if last_ship_event.payout.present?
    # Only an approved ship that is still awaiting its payout should block the
    # next ship. A ship that's pending, returned for changes, or rejected isn't
    # a "previous ship awaiting payout" — it's the one currently being
    # (re-)certified, so it must not block re-certification.
    return true unless last_ship_event.certification_status == "approved"
    # with_deleted so a fixed-prize ship whose mission was detached doesn't
    # strand the project: Post::ShipEvent.voteable keeps that ship out of the
    # rating pool either way, so no payout is ever coming for it.
    sub = Mission::Submission.with_deleted.find_by(ship_event_id: last_ship_event.id)
    return true if sub&.payout_path == "static_prize"
    false
  end

  def ensure_hackatime_projects
    Project::EnsureHackatimeProjectsJob.perform_later(id)
  end

  def notify_slack_channel
    PostCreationToSlackJob.perform_later(self)
  end
end
