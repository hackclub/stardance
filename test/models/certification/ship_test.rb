# frozen_string_literal: true

# == Schema Information
#
# Table name: certification_ship_reviews
#
#  id                        :bigint           not null, primary key
#  bonus_stardust            :float
#  claim_expires_at          :datetime
#  claimed_at                :datetime
#  decided_at                :datetime
#  feedback                  :text
#  internal_reason           :text
#  lock_version              :integer          default(0), not null
#  proof_video_url           :string
#  recert_reason             :text
#  reversed_at               :datetime
#  stardust_earned           :float
#  status                    :integer          default(0), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  external_certification_id :string
#  post_ship_event_id        :bigint
#  project_id                :bigint           not null
#  returned_by_id            :bigint
#  reviewer_id               :bigint
#
# Indexes
#
#  idx_on_status_claim_expires_at_c7a5e87a52                      (status,claim_expires_at)
#  index_certification_ship_reviews_on_decided_at                 (decided_at)
#  index_certification_ship_reviews_on_external_certification_id  (external_certification_id) UNIQUE
#  index_certification_ship_reviews_on_post_ship_event_id         (post_ship_event_id)
#  index_certification_ship_reviews_on_reviewer_id                (reviewer_id)
#  index_ship_reviews_unique_pending_project                      (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (post_ship_event_id => post_ship_events.id) ON DELETE => nullify
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

  test "software_only excludes ships whose project has a hardware stage" do
    software = @project.ship_reviews.create!(status: :pending)
    hardware = hardware_project.ship_reviews.create!(status: :pending)

    ids = Certification::Ship.software_only.pluck(:id)

    assert_includes ids, software.id
    refute_includes ids, hardware.id
  end

  test "dashboard_stats counts software ships only" do
    @project.ship_reviews.create!(status: :pending)
    hardware_project.ship_reviews.create!(status: :pending)

    assert_equal 1, Certification::Ship.dashboard_stats[:pending]
  end

  # The projects join makes bare `created_at` ambiguous in Postgres, so these
  # two keys are the ones that break if a query loses its table qualifier.
  test "dashboard_stats resolves created_at against the reviews table" do
    @project.ship_reviews.create!(status: :pending, created_at: 10.days.ago)
    decided = @project.ship_reviews.create!(status: :approved, reviewer: @reviewer)
    decided.update_columns(created_at: 5.days.ago, decided_at: 4.days.ago)

    stats = Certification::Ship.dashboard_stats

    assert_equal 1, stats[:overdue_pending]
    assert_in_delta 24.0, stats[:avg_decision_hours], 0.5
  end

  test "next_eligible never hands a shipwright a hardware ship" do
    @reviewer.grant_role!(:project_certifier)
    hardware = hardware_project.ship_reviews.create!(status: :pending)

    assert_nil Certification::Ship.next_eligible(@reviewer)

    software = @project.ship_reviews.create!(status: :pending)
    assert_equal software.id, Certification::Ship.next_eligible(@reviewer).id
    refute_equal hardware.id, Certification::Ship.next_eligible(@reviewer).id
  end

  # Action items only gate the hardware build flow. A software Shipwright's
  # dashed feedback (the "Doesn't meet quality standards" template ships with
  # bullets) must not turn resubmission into an acknowledgment checklist.
  test "gates_resubmission? fires for a hardware ship with action items" do
    review = Certification::Ship.new(feedback: "nearly there\n- add a BOM",
                                     project: Project.new(hardware_stage: "build"))

    assert review.gates_resubmission?
  end

  test "gates_resubmission? never fires for a software ship, even with dashed feedback" do
    review = Certification::Ship.new(feedback: "nearly there\n- rework the CSS",
                                     project: Project.new(hardware_stage: nil))

    assert_not review.gates_resubmission?
  end

  private

  def hardware_project(stage: "build")
    project = Project.create!(title: "Hardware Ship", description: "A hardware build", ship_status: "submitted")
    project.memberships.create!(user: @owner, role: :owner)
    project.update!(hardware_stage: stage)
    project
  end
end
