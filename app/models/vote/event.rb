# == Schema Information
#
# Table name: vote_events
#
#  id                 :bigint           not null, primary key
#  event_type         :string           not null
#  ip                 :string
#  occurred_at        :datetime         not null
#  properties         :jsonb            not null
#  source             :string           default("server"), not null
#  user_agent         :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  ahoy_visit_id      :bigint
#  project_id         :bigint
#  ship_event_id      :bigint
#  user_id            :bigint           not null
#  vote_assignment_id :bigint
#  vote_id            :bigint
#
# Indexes
#
#  index_vote_events_on_ahoy_visit_id               (ahoy_visit_id)
#  index_vote_events_on_event_type_and_occurred_at  (event_type,occurred_at)
#  index_vote_events_on_project_id                  (project_id)
#  index_vote_events_on_properties                  (properties) USING gin
#  index_vote_events_on_ship_event_id               (ship_event_id)
#  index_vote_events_on_user_id                     (user_id)
#  index_vote_events_on_vote_assignment_id          (vote_assignment_id)
#  index_vote_events_on_vote_id                     (vote_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (vote_assignment_id => vote_assignments.id)
#  fk_rails_...  (vote_id => votes.id)
#
class Vote::Event < ApplicationRecord
  SOURCES = %w[server client].freeze

  SERVER_EVENT_TYPES = %w[
    vote_assignment_assigned
    vote_assignment_viewed
    vote_assignment_expired
    vote_assignment_replaced
    vote_submit_attempted
    vote_submitted
    vote_skipped
    vote_demo_opened
    vote_repo_opened
  ].freeze

  CLIENT_EVENT_TYPES = %w[
    vote_visibility_ping
    vote_scroll_depth
    vote_timeline_item_read
    vote_score_changed
    vote_feedback_pasted
    vote_feedback_changed
  ].freeze

  EVENT_TYPES = (SERVER_EVENT_TYPES + CLIENT_EVENT_TYPES).freeze

  belongs_to :user
  belongs_to :vote_assignment, class_name: "Vote::Assignment", inverse_of: :events, optional: true
  belongs_to :vote, inverse_of: :events, optional: true
  belongs_to :project, optional: true
  belongs_to :ship_event, class_name: "Post::ShipEvent", optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :occurred_at, presence: true

  attribute :occurred_at, default: -> { Time.current }
  attribute :source, default: "server"

  scope :server, -> { where(source: "server") }
  scope :client, -> { where(source: "client") }
  scope :of_type, ->(type) { where(event_type: type) }
end
