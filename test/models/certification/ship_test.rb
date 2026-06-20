# frozen_string_literal: true

# == Schema Information
#
# Table name: certification_ship_reviews
#
#  id               :bigint           not null, primary key
#  claim_expires_at :datetime
#  claimed_at       :datetime
#  decided_at       :datetime
#  feedback         :text
#  internal_reason  :text
#  lock_version     :integer          default(0), not null
#  recert_reason    :text
#  stardust_earned  :integer
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  project_id       :bigint           not null
#  returned_by_id   :bigint
#  reviewer_id      :bigint
#
# Indexes
#
#  idx_on_status_claim_expires_at_c7a5e87a52        (status,claim_expires_at)
#  index_certification_ship_reviews_on_decided_at   (decided_at)
#  index_certification_ship_reviews_on_reviewer_id  (reviewer_id)
#  index_ship_reviews_unique_pending_project        (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#
require "test_helper"

class Certification::ShipTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_SHIP_OWNER", display_name: "shipowner")
    @owner.update!(slack_id: nil, verification_status: "verified")
    @reviewer = create_user(slack_id: "U_SHIP_REVIEWER", display_name: "shipreviewer")
    @outsider = create_user(slack_id: "U_SHIP_OUTSIDER", display_name: "shipoutsider")
    @contributor = create_user(slack_id: "U_SHIP_CONTRIBUTOR", display_name: "shipcontributor")

    @project = Project.create!(
      title: "Visible Verdicts",
      description: "A project with review feedback",
      ship_status: "submitted"
    )
    @project.memberships.create!(user: @owner, role: :owner)
    @project.memberships.create!(user: @contributor, role: :contributor)
  end

  test "submitter_history aggregates verdicts across the owner's projects" do
    other = Project.create!(title: "Second Ship", description: "Another one", ship_status: "submitted")
    other.memberships.create!(user: @owner, role: :owner)

    returned = @project.ship_reviews.create!(status: :returned, feedback: "Fix the README.", reviewer: @reviewer)
    approved = other.ship_reviews.create!(status: :approved, reviewer: @reviewer)
    pending = other.ship_reviews.create!(status: :pending)

    outsider_project = Project.create!(title: "Not Theirs", description: "Someone else's", ship_status: "submitted")
    outsider_project.memberships.create!(user: @outsider, role: :owner)
    outsider_project.ship_reviews.create!(status: :approved, reviewer: @reviewer)

    history = Certification::Ship.submitter_history(@owner)

    assert_equal 3, history[:total]
    assert_equal 2, history[:projects]
    assert_equal 1, history[:approved]
    assert_equal 1, history[:returned]
    assert_equal [ pending.id, approved.id, returned.id ], history[:recent].map(&:id)

    assert_equal 0, Certification::Ship.submitter_history(@contributor)[:total]
  end

  test "submitter_history caps recent at six and keeps soft-deleted projects" do
    reviews = 7.times.map { @project.ship_reviews.create!(status: :approved, reviewer: @reviewer) }
    @project.soft_delete!(force: true)

    history = Certification::Ship.submitter_history(@owner)

    assert_equal 7, history[:total]
    assert_equal 1, history[:projects]
    assert_equal 6, history[:recent].size
    assert_equal reviews.last.id, history[:recent].first.id
    assert history[:recent].first.project_with_deleted.deleted?
  end
end
