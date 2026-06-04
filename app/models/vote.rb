# == Schema Information
#
# Table name: votes
#
#  id                 :bigint           not null, primary key
#  originality_score  :integer
#  reason             :text
#  storytelling_score :integer
#  technical_score    :integer
#  usability_score    :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  project_id         :bigint           not null
#  ship_event_id      :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_votes_on_project_id                 (project_id)
#  index_votes_on_ship_event_id              (ship_event_id)
#  index_votes_on_user_id                    (user_id)
#  index_votes_on_user_id_and_ship_event_id  (user_id,ship_event_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#  fk_rails_...  (user_id => users.id)
#
class Vote < ApplicationRecord
  MIN_SCORE = 1
  MAX_SCORE = 9

  CATEGORIES = {
    originality: "How distinct is the project from common projects?",
    technicality: "How much effort did the creator put into the implementation?",
    usability: "Did you like using it? Could you use it at all?",
    storytelling: "How well does the creator document the development journey through devlogs, documentation, commit messages, and READMEs?"
  }.freeze

  SCORE_COLUMNS_BY_CATEGORY = {
    originality: :originality_score,
    technicality: :technical_score,
    usability: :usability_score,
    storytelling: :storytelling_score
  }.freeze

  def self.score_columns = SCORE_COLUMNS_BY_CATEGORY.values

  belongs_to :user, counter_cache: true
  belongs_to :project
  belongs_to :ship_event, class_name: "Post::ShipEvent", counter_cache: true

  has_one :assignment, class_name: "Vote::Assignment", dependent: :nullify

  has_paper_trail on: [ :create, :update, :destroy ]

  after_commit :increment_user_vote_balance, on: :create
  after_create_commit :send_gorse_vote_later

  scope :payout_countable, -> { all }

  validates :reason, presence: true
  validate :reason_minimum_words
  validates(*score_columns,
    presence: { message: "must be scored" },
    numericality: { only_integer: true, in: MIN_SCORE..MAX_SCORE, message: "must be between #{MIN_SCORE} and #{MAX_SCORE}" })
  validate :user_cannot_vote_on_own_projects
  validate :ship_event_matches_project

  private

  # Validations

  def reason_minimum_words
    return if reason.blank?

    word_count = reason.split(/\s+/).count
    errors.add(:reason, "must be at least 10 words (you have #{word_count})") if word_count < 10
  end

  def user_cannot_vote_on_own_projects
    errors.add(:user, "cannot vote on own projects") if project&.users&.exists?(user_id)
  end

  def ship_event_matches_project
    return if ship_event.blank? || project_id.blank?

    expected_project_id = ship_event.post&.project_id
    return if expected_project_id.blank?

    errors.add(:project, "does not match ship event") if project_id != expected_project_id
  end

  # Callback

  def increment_user_vote_balance
    user.increment!(:vote_balance, 1)
  end

  def send_gorse_vote_later
    if ship_event&.post.present?
      send_gorse_feedback_later(
        user: user,
        item: ship_event.post,
        feedback_type: :vote,
        value: score_average,
        timestamp: created_at
      )
    end
  end

  def score_average
    scores = self.class.score_columns.filter_map { |column| public_send(column) }
    if scores.any?
      scores.sum.to_f / scores.size
    else
      1
    end
  end
end
