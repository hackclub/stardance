# == Schema Information
#
# Table name: vote_assignments
#
#  id            :bigint           not null, primary key
#  status        :string           default("assigned"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  ship_event_id :bigint           not null
#  user_id       :bigint           not null
#  vote_id       :bigint
#
# Indexes
#
#  index_vote_assignments_on_ship_event_id              (ship_event_id)
#  index_vote_assignments_on_user_id                    (user_id)
#  index_vote_assignments_on_user_id_and_ship_event_id  (user_id,ship_event_id) UNIQUE
#  index_vote_assignments_on_user_id_and_status         (user_id,status)
#  index_vote_assignments_on_vote_id                    (vote_id)
#
# Foreign Keys
#
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (vote_id => votes.id)
#
class Vote::Assignment < ApplicationRecord
  STATUSES = %w[assigned submitted skipped].freeze

  belongs_to :user
  belongs_to :ship_event, class_name: "Post::ShipEvent", inverse_of: :vote_assignments
  belongs_to :vote, optional: true

  enum :status, {
    assigned: "assigned",
    submitted: "submitted",
    skipped: "skipped"
  }, default: :assigned

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :ship_event_id }
  validate :ship_event_can_be_assigned, on: :create

  def self.current_for(user)
    assigned
      .joins(ship_event: :post)
      .where(user: user)
      .order(created_at: :desc)
      .first
  end

  def self.assign_to(user)
    current_for(user) || assign_new_to(user)
  end

  def submit_vote(attributes)
    vote = build_vote(attributes.merge(user: user, ship_event: ship_event, project: ship_event.project))

    transaction do
      vote.save!
      update!(status: :submitted, vote: vote)
    end

    vote
  rescue ActiveRecord::RecordInvalid
    vote
  end

  def skip
    transaction do
      update!(status: :skipped)
      send_gorse_skip_later
    end
  end

  private
    def self.assign_new_to(user)
      if ship_event = assignable_ship_events_for(user).order(Arel.sql("RANDOM()")).first
        create!(user: user, ship_event: ship_event)
      end
    end

    def self.assignable_ship_events_for(user)
      excluded_ship_event_ids = where(user: user).where(status: %w[submitted skipped]).select(:ship_event_id)
      voted_ship_event_ids = Vote.where(user: user).select(:ship_event_id)
      own_ship_event_ids = Post::ShipEvent
        .joins(post: { project: :memberships })
        .where(project_memberships: { user_id: user.id })
        .select(:id)

      Post::ShipEvent
        .joins(:post)
        .where(certification_status: %w[pending approved])
        .where.not(id: excluded_ship_event_ids)
        .where.not(id: voted_ship_event_ids)
        .where.not(id: own_ship_event_ids)
    end

    def ship_event_can_be_assigned
      unless ship_event&.certification_status.in?(%w[pending approved])
        errors.add(:ship_event, "must be pending or approved")
      end
    end

    def send_gorse_skip_later
      if ship_event&.post.present?
        send_gorse_feedback_later(user: user, item: ship_event.post, feedback_type: :skip)
      end
    end
end
