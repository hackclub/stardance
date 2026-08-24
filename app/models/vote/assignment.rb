# == Schema Information
#
# Table name: vote_assignments
#
#  id              :bigint           not null, primary key
#  first_viewed_at :datetime
#  last_viewed_at  :datetime
#  skipped_at      :datetime
#  status          :string           default("assigned"), not null
#  submitted_at    :datetime
#  view_count      :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  ship_event_id   :bigint           not null
#  user_id         :bigint           not null
#  vote_id         :bigint
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
  STATUSES = %w[assigned submitted skipped expired].freeze

  belongs_to :user
  belongs_to :ship_event, class_name: "Post::ShipEvent", inverse_of: :vote_assignments
  belongs_to :vote, optional: true

  has_many :events, class_name: "Vote::Event",
                    foreign_key: :vote_assignment_id,
                    inverse_of: :vote_assignment,
                    dependent: :nullify

  enum :status, {
    assigned: "assigned",
    submitted: "submitted",
    skipped: "skipped",
    expired: "expired"
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

  def self.assign_to(user, user_agent: nil)
    matchmaker = Vote::Matchmaker.new(user, user_agent: user_agent)

    if current = current_for(user)
      current.refresh(matchmaker)
    else
      assign_new_to(user, matchmaker)
    end
  end

  def refresh(matchmaker = Vote::Matchmaker.new(user))
    # Hardware left the rating pool, but assignments handed out before that
    # would keep being served: the branches below only swap a ship out once it's
    # rejected or already paid.
    if ship_event.project&.hardware?
      replace_with(matchmaker.next_ship_event)
    elsif !ship_event.voting_links_present?
      replace_with(matchmaker.next_ship_event)
    elsif ship_event.certification_status.in?(Post::ShipEvent::HIDDEN_STATUSES)
      replace_with(matchmaker.next_ship_event)
    elsif ship_event.payout.present? || ship_event.votes.payout_countable.count >= Post::ShipEvent::VOTES_TO_LEAVE_POOL
      if replacement = matchmaker.next_unpaid_ship_event
        replace_with(replacement)
      elsif matchmaker.paid_fallback_allowed?
        self
      else
        replace_with(nil)
      end
    else
      self
    end
  end

  def submit_vote(attributes)
    vote = build_vote(attributes.merge(
      user: user,
      ship_event: ship_event,
      project: ship_event.project
    ).merge(readable_telemetry_attributes))

    transaction do
      vote.save!
      update!(status: :submitted, vote: vote, submitted_at: Time.current)
      events.where(vote_id: nil).update_all(vote_id: vote.id)
    end

    vote
  rescue ActiveRecord::RecordInvalid
    vote
  end

  def skip
    transaction do
      update!(status: :skipped, skipped_at: Time.current)
      send_gorse_skip_later
    end
  end

  def mark_viewed!
    now = Time.current
    update_columns(
      first_viewed_at: first_viewed_at || now,
      last_viewed_at: now,
      view_count: view_count + 1,
      updated_at: now
    )
  end

  def readable_telemetry_attributes(now: Time.current)
    {
      time_taken_to_vote_in_seconds: first_viewed_at && (now - first_viewed_at).round,
      demo_opened: events.of_type("vote_demo_opened").exists?,
      repo_opened: events.of_type("vote_repo_opened").exists?
    }
  end

  private
    def self.assign_new_to(user, matchmaker)
      if ship_event = matchmaker.next_ship_event
        assignment = create!(user: user, ship_event: ship_event)
        VoteTelemetry.record("vote_assignment_assigned", user: user, assignment: assignment)
        assignment
      end
    end

    def replace_with(replacement_ship_event)
      transaction do
        update!(status: :expired)
        VoteTelemetry.record("vote_assignment_expired", user: user, assignment: self,
                             properties: { reason: "replaced" })

        if replacement_ship_event
          replacement = self.class.create!(user: user, ship_event: replacement_ship_event)
          VoteTelemetry.record("vote_assignment_replaced", user: user, assignment: replacement,
                               properties: { replaced_assignment_id: id })
          replacement
        end
      end
    end

    def ship_event_can_be_assigned
      unless ship_event&.certification_status == "approved"
        errors.add(:ship_event, "must be approved")
      end

      unless ship_event&.voting_links_present?
        errors.add(:ship_event, "must have both a demo and repository link")
      end
    end

    def send_gorse_skip_later
      if ship_event&.post.present?
        send_gorse_feedback_later(user: user, item: ship_event.post, feedback_type: :skip)
      end
    end
end
