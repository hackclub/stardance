# == Schema Information
#
# Table name: poll_votes
#
#  id         :bigint           not null, primary key
#  choice     :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_poll_votes_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
# One vote per user in the "hi what up. we have a question" popup poll.
class PollVote < ApplicationRecord
  DISMISS_THING = "jimberjake_poll"
  STREAM = "jimberjake_poll"
  YOUTUBE_ID = "uREQnxLW8CU"
  CHOICES = {
    "justin" => "justin jimberjake",
    "melena" => "melena momez"
  }.freeze

  belongs_to :user

  validates :choice, inclusion: { in: CHOICES.keys }
  validates :user_id, uniqueness: true

  after_create_commit :broadcast_results

  def self.tally
    counts = group(:choice).count
    CHOICES.keys.index_with { |choice| counts.fetch(choice, 0) }
  end

  private
    # Pushes fresh numbers to everyone already looking at the results
    # (voters with the popup open and the admin results page).
    def broadcast_results
      broadcast_replace_to STREAM, target: "poll-results", partial: "poll_votes/results", locals: { tally: self.class.tally }
    end
end
