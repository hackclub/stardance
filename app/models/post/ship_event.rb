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
#  multiplier                 :float
#  originality_median         :decimal(5, 2)
#  originality_percentile     :decimal(5, 2)
#  overall_percentile         :decimal(5, 2)
#  overall_score              :decimal(5, 2)
#  payout                     :float
#  payout_basis_locked_at     :datetime
#  payout_basis_overall_score :decimal(5, 2)
#  payout_basis_percentile    :decimal(5, 2)
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
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
class Post::ShipEvent < ApplicationRecord
  include Postable
  include Ledgerable
  include SemanticSearchIndexable
  semantic_search_indexable type: "ship"

  VOTES_REQUIRED_FOR_PAYOUT = 12
  VOTES_TO_LEAVE_POOL = VOTES_REQUIRED_FOR_PAYOUT
  VOTE_COST_PER_SHIP = 15
  BODY_MAX_LENGTH = Post::Devlog::BODY_MAX_LENGTH
  REVIEW_INSTRUCTIONS_MAX_LENGTH = 2_000
  MAX_ATTACHMENTS = 2
  ACCEPTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/gif].freeze

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

  after_update :sync_mission_submission_status, if: :saved_change_to_certification_status?

  scope :voteable, -> {
    where(certification_status: "approved", payout: nil)
      .where("post_ship_events.votes_count < ?", VOTES_TO_LEAVE_POOL)
      .where("post_ship_events.hours_at_ship > 0")
      .where.not(id: Mission::Submission.where(deleted_at: nil, payout_path: "static_prize").select(:ship_event_id))
  }
  scope :paid_out, -> { where(certification_status: "approved").where.not(payout: nil) }

  after_commit :decrement_user_vote_balance, on: :create
  after_commit :schedule_type_check, on: :create

  validates :body, presence: { message: "Update message can't be blank" }
  validates :body, length: { maximum: BODY_MAX_LENGTH }, on: :create
  validates :review_instructions, length: { maximum: REVIEW_INSTRUCTIONS_MAX_LENGTH }, allow_blank: true
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
    reload.recalculate_hours_at_ship
  end

  def recalculate_hours_at_ship
    update!(hours_at_ship: hours_logged_in_ship_window)
  end

  private

  def hours_logged_in_ship_window
    return 0 unless post&.project && post.created_at

    project.posts.of_devlogs(join: true)
           .where("posts.created_at >= ? AND posts.created_at <= ?", ship_window_start_time, post.created_at)
           .where(post_devlogs: { deleted_at: nil })
           .sum("post_devlogs.duration_seconds")
           .to_f / 3600
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

    post.user.increment!(:vote_balance, -VOTE_COST_PER_SHIP)
  end

  def schedule_type_check
    project = post&.project
    Project::TypeCheckJob.perform_later(project) if project && project.project_type.nil?
  end

  # Drives the Mission::Submission state machine off ship cert transitions.
  # See docs/missions-design.md "Certification interaction" for the spec.
  def sync_mission_submission_status
    submission = mission_submission
    return unless submission

    case certification_status
    when "approved"
      submission.certify! if submission.may_certify?
    when "rejected"
      if submission.may_fail_certification?
        submission.update_columns(rejection_message: "Ship was not certified — see ship feedback for details.")
        submission.fail_certification!
      end
    end
  end
end
