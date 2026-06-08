# == Schema Information
#
# Table name: post_ship_events
#
#  id                         :bigint           not null, primary key
#  base_hours                 :float
#  body                       :string
#  bridge                     :boolean          default(FALSE), not null
#  certification_status       :string           default("pending")
#  feedback_reason            :text
#  feedback_video_url         :string
#  hours                      :float
#  legacy_payout_deduction    :float
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
#  voting_scale_version       :integer          default(2), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
class Post::ShipEvent < ApplicationRecord
  include Postable
  include Ledgerable
  include SemanticSearchIndexable
  semantic_search_indexable type: "ship"

  LEGACY_VOTING_SCALE_VERSION = 1
  CURRENT_VOTING_SCALE_VERSION = 2
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

  has_one :mission_submission, class_name: "Mission::Submission",
                               foreign_key: :ship_event_id,
                               inverse_of: :ship_event,
                               dependent: :destroy

  after_update :sync_mission_submission_status, if: :saved_change_to_certification_status?

  scope :current_voting_scale, -> { where(voting_scale_version: CURRENT_VOTING_SCALE_VERSION) }
  scope :legacy_voting_scale, -> { where(voting_scale_version: LEGACY_VOTING_SCALE_VERSION) }

  after_commit :decrement_user_vote_balance, on: :create

  validates :body, presence: { message: "Update message can't be blank" }
  validates :body, length: { maximum: BODY_MAX_LENGTH }, on: :create
  validates :review_instructions, length: { maximum: REVIEW_INSTRUCTIONS_MAX_LENGTH }, allow_blank: true
  validate :project_can_be_shipped, on: :create
  has_paper_trail ignore: [ :votes_count, :synced_at ]

  def majority_judgment
    MajorityJudgmentService.call(self)
  end

  # Hours that form the voting payout basis. Software projects count every
  # logged second (unchanged). Hardware projects only pay for build-phase time,
  # after reviewer deflation: where a Certification::Devlog review exists we use
  # the reviewer-approved minutes (rejected => 0), otherwise the raw logged time
  # so voting can begin before review completes. Design-phase time never pays.
  def hours
    project = post&.project
    return 0 unless project && created_at

    ship_event_post = post
    previous_ship_event_post = project.posts.of_ship_events
                                      .where("posts.created_at < ?", ship_event_post.created_at)
                                      .order("posts.created_at DESC")
                                      .first

    # created_at if first otherwise use the last ship_event
    start_time = previous_ship_event_post ? previous_ship_event_post.created_at : project.created_at

    devlog_scope = project.posts.of_devlogs(join: true)
                          .where("posts.created_at >= ? AND posts.created_at <= ?", start_time, ship_event_post.created_at)
                          .where(post_devlogs: { deleted_at: nil })

    unless project.hardware?
      seconds = devlog_scope.sum("post_devlogs.duration_seconds")
      return seconds.to_f / 3600
    end

    devlogs = Post::Devlog.where(id: devlog_scope.select("posts.postable_id"))
                          .includes(:devlog_review)

    minutes = devlogs.sum do |devlog|
      next 0 unless devlog.phase == "build"

      review = devlog.devlog_review
      if review&.reviewed?
        review.approved_minutes.to_i
      else
        (devlog.duration_seconds || 0).to_f / 60.0
      end
    end

    minutes / 60.0
  end

  def payout_eligible?
    return false unless certification_status == "approved"
    return false unless current_voting_scale?
    return false unless payout.blank?
    return false unless votes.payout_countable.count >= VOTES_REQUIRED_FOR_PAYOUT

    payout_user = payout_recipient
    return false unless payout_user
    return false if payout_user.vote_balance < 0

    true
  end

  def payout_recipient
    post&.user
  end

  def current_voting_scale?
    voting_scale_version == CURRENT_VOTING_SCALE_VERSION
  end

  def legacy_voting_scale?
    voting_scale_version == LEGACY_VOTING_SCALE_VERSION
  end

  private

  def project_can_be_shipped
    return unless project
    project.ship_blocking_errors.each { |msg| errors.add(:base, msg) }
  end

  def decrement_user_vote_balance
    return unless post&.user
    return if mission_submission&.payout_path == "static_prize"

    post.user.increment!(:vote_balance, -VOTE_COST_PER_SHIP)
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
