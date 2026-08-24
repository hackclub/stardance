# == Schema Information
#
# Table name: post_ship_events
#
#  id                         :bigint           not null, primary key
#  body                       :string
#  certification_status       :string           default("pending")
#  feedback_reason            :text
#  feedback_video_url         :string
#  hours_at_payout            :float
#  hours_at_ship              :float
#  lifecycle_data_quality     :string
#  multiplier                 :float
#  originality_median         :decimal(5, 2)
#  originality_percentile     :decimal(5, 2)
#  overall_percentile         :decimal(5, 2)
#  overall_score              :decimal(5, 2)
#  paid_at                    :datetime
#  payout                     :float
#  payout_basis_locked_at     :datetime
#  payout_basis_overall_score :decimal(5, 2)
#  payout_basis_percentile    :decimal(5, 2)
#  payout_basis_vote_ids      :bigint           default([]), not null, is an Array
#  payout_blessing            :string
#  payout_curve_version       :string
#  review_instructions        :text
#  storytelling_median        :decimal(5, 2)
#  storytelling_percentile    :decimal(5, 2)
#  synced_at                  :datetime
#  technical_median           :decimal(5, 2)
#  technical_percentile       :decimal(5, 2)
#  usability_median           :decimal(5, 2)
#  usability_percentile       :decimal(5, 2)
#  votes_count                :integer          default(0), not null
#  voting_completed_at        :datetime
#  voting_started_at          :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
# Indexes
#
#  index_post_ship_events_on_paid_at              (paid_at)
#  index_post_ship_events_on_voting_completed_at  (voting_completed_at)
#  index_post_ship_events_on_voting_started_at    (voting_started_at)
#
class Post::ShipEvent < ApplicationRecord
  include Postable
  include Ledgerable
  include Post::ShipEvent::Payouts
  include SemanticSearchIndexable
  semantic_search_indexable type: "ship"

  VOTES_REQUIRED_FOR_PAYOUT = 12
  VOTES_TO_LEAVE_POOL = VOTES_REQUIRED_FOR_PAYOUT
  VOTE_COST_PER_SHIP = 18
  MAX_PAYOUT_HOURS_PER_DEVLOG = 10
  MAX_PAYOUT_SECONDS_PER_DEVLOG = MAX_PAYOUT_HOURS_PER_DEVLOG.hours.to_i
  # Un-devlogged time at which the UI and DevlogCapWarningJob start nudging
  # users to post before they hit the per-devlog payout cap.
  DEVLOG_CAP_WARNING_SECONDS = 8.hours.to_i
  BODY_MAX_LENGTH = Post::Devlog::BODY_MAX_LENGTH
  REVIEW_INSTRUCTIONS_MAX_LENGTH = 2_000
  RETURN_REASON_MAX_LENGTH = 1_000
  UNCERTIFIED_SUBMISSION_MESSAGE = "Your ship was not certified. See the ship feedback for what to change."
  MAX_ATTACHMENTS = 2
  ACCEPTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/gif].freeze
  LIFECYCLE_DATA_QUALITIES = %w[live backfilled_exact backfilled_estimated].freeze
  # Certification statuses that take a ship out of every public surface: the
  # feed, the profile, search, recommendations, and the voting pool. "rejected"
  # is a verdict; "misfiled" is a reviewer saying the ship went to the wrong
  # queue, which the owner still sees on their own project page so they can
  # answer it (see Project::QueueMismatch).
  HIDDEN_STATUSES = %w[rejected misfiled].freeze

  include HasPostAttachments

  has_one :project, through: :post
  has_many :project_memberships, through: :project, source: :memberships
  has_many :project_members, through: :project, source: :users

  has_many :votes, foreign_key: :ship_event_id, dependent: :nullify, inverse_of: :ship_event
  has_many :vote_assignments, class_name: "Vote::Assignment",
                              foreign_key: :ship_event_id,
                              dependent: :destroy,
                              inverse_of: :ship_event
  has_many :vote_events, class_name: "Vote::Event",
                         foreign_key: :ship_event_id,
                         dependent: :nullify,
                         inverse_of: :ship_event

  has_one :mission_submission, class_name: "Mission::Submission",
                               foreign_key: :ship_event_id,
                               inverse_of: :ship_event,
                               dependent: :destroy

  has_one :integrity_check, class_name: "Certification::Integrity",
                            foreign_key: :ship_event_id,
                            inverse_of: :ship_event,
                            dependent: :destroy

  before_save :stamp_rating_lifecycle
  after_update :sync_mission_submission_status, if: :saved_change_to_certification_status?
  after_commit :sync_post_to_gorse_after_certification_change,
               on: :update,
               if: :saved_change_to_certification_status?

  scope :voteable, -> {
    where(certification_status: "approved", payout: nil)
      .where(Vote.countable_count_lt(VOTES_TO_LEAVE_POOL))
      .where("post_ship_events.hours_at_ship > 0")
      .joins(:project)
      .where.not(projects: { demo_url: [ nil, "" ] })
      .where.not(projects: { repo_url: [ nil, "" ] })
      .where.not(id: Mission::Submission.with_deleted.where(payout_path: "static_prize").select(:ship_event_id))
  }

  def voting_links_present?
    project&.demo_url.present? && project&.repo_url.present?
  end

  scope :paid_out, -> { where(certification_status: "approved").where.not(payout: nil) }

  after_commit :decrement_user_vote_balance, on: :create
  after_commit :schedule_type_check, on: :create

  validates :body, presence: { message: "Update message can't be blank" }
  validates :body, length: { maximum: BODY_MAX_LENGTH }, on: :create
  validates :review_instructions, length: { maximum: REVIEW_INSTRUCTIONS_MAX_LENGTH }, allow_blank: true
  validates :lifecycle_data_quality, inclusion: { in: LIFECYCLE_DATA_QUALITIES }, allow_nil: true
  validate :project_can_be_shipped, on: :create
  has_paper_trail ignore: [ :votes_count, :synced_at ]

  def self.recalculate_hours_for_devlog_post(post)
    return unless post&.project

    post.project.posts.of_ship_events
        .where("posts.created_at >= ?", post.created_at)
        .order(:created_at)
        .first
        &.postable
        &.recalculate_hours_at_ship
  end

  def capture_hours_at_ship
    association(:post).reset
    association(:project).reset
    recalculate_hours_at_ship
  end

  def recalculate_hours_at_ship
    update!(hours_at_ship: hours_logged_in_ship_window)
  end

  # All non-deleted devlogs in this ship's window, regardless of phase or
  # funding — unlike hours_at_ship, which on hardware drops explicit design
  # work and anything logged before the funding request.
  def window_devlogs_count
    return 0 unless post&.project && post.created_at

    window_devlogs.count
  end

  private

  def stamp_rating_lifecycle
    if will_save_change_to_certification_status? && certification_status == "approved" && voting_started_at.nil?
      self.voting_started_at = Time.current
      self.lifecycle_data_quality ||= "live"
    end

    if will_save_change_to_payout? && payout.present? && paid_at.nil?
      self.paid_at = Time.current
      self.lifecycle_data_quality ||= "live"
    end
  end

  def hours_logged_in_ship_window
    return 0 unless post&.project && post.created_at

    devlogs_in_ship_window.sum("post_devlogs.duration_seconds").to_f / 3600
  end

  # Hardware pays for build time, not the design work the grant was awarded
  # against. Explicit design-phase time is dropped; build time counts, and so
  # does software time (phase nil) carried over from a project that started as
  # software and converted to hardware later. On top of that the funding
  # request, when there is one, is the real build boundary: anything logged
  # before it is pre-funding and doesn't count, whatever its phase. A project
  # that skipped funding has no cutoff, so all of its non-design time counts
  # back to the project's start.
  def devlogs_in_ship_window
    return window_devlogs unless project.hardware?

    scope = window_devlogs.where("post_devlogs.phase IS DISTINCT FROM 'design'")
    cutoff = hardware_payout_cutoff
    cutoff ? scope.where("posts.created_at >= ?", cutoff) : scope
  end

  def window_devlogs
    project.posts.of_devlogs(join: true)
           .where("posts.created_at >= ? AND posts.created_at <= ?", ship_window_start_time, post.created_at)
           .where(post_devlogs: { deleted_at: nil })
  end

  def ship_window_start_time
    project.posts.of_ship_events
           .where("posts.created_at < ?", post.created_at)
           .maximum(:created_at) || project.created_at
  end

  def project_can_be_shipped
    return unless project
    project.ship_blocking_errors.each { |msg| errors.add(:base, msg) }
  end

  def decrement_user_vote_balance
    return unless post&.user
    return if mission_submission&.payout_path == "static_prize"
    # Vote debt buys a place in the rating pool. Hardware never enters it, so
    # charging for a ship the builder can't work off would strand them.
    return if project&.hardware?

    post.user.increment!(:vote_balance, -VOTE_COST_PER_SHIP)
  end

  def schedule_type_check
    project = post&.project
    Project::TypeCheckJob.perform_later(project) if project && project.project_type.nil?
  end

  # Drives the Mission::Submission state machine off ship cert transitions.
  # See docs/missions-design.md "Certification interaction" for the spec.
  # "returned" is the verdict the ship queue actually writes; "rejected" only
  # comes from an admin forcing the project state.
  def sync_mission_submission_status
    submission = mission_submission
    return unless submission

    case certification_status
    when "approved"
      if submission.may_certify?
        submission.certify!
      elsif failed_certification?(submission)
        submission.update_columns(rejection_message: nil)
        submission.undo!
      end
    when "returned", "rejected"
      if submission.may_fail_certification?
        submission.update_columns(rejection_message: UNCERTIFIED_SUBMISSION_MESSAGE)
        submission.fail_certification!
      end
    end
  end

  def sync_post_to_gorse_after_certification_change
    post&.sync_to_gorse_later
  end

  # A submission certification knocked back, as opposed to one a mission
  # reviewer judged: only the reviewer path stamps reviewed_by, and their
  # verdict has to survive a later re-certification.
  def failed_certification?(submission)
    submission.rejected? && submission.reviewed_by_id.nil?
  end
end
