require "test_helper"

class OneTime::SyncIntegrityStatusToAirtableJobTest < ActiveSupport::TestCase
  setup do
    @owner   = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "user#{SecureRandom.hex(4)}")
    @project = create_project
    @review  = create_synced_ysws_review(@project)
    @integrity = create_integrity(@review.post_ship_event, status: :pending)
  end

  test "writes the current status to Airtable and stamps the review as synced" do
    decide!(:banned)
    record = FakeAirtableRecord.new(fields: { "integrity_status" => "pending" })

    assert stub_airtable_record(record) { perform }

    assert_equal "banned", record["integrity_status"]
    assert_equal [ "integrity_status" ], record.saved_fields
    assert @review.reload.airtable_synced_at > @integrity.updated_at
  end

  test "writes nothing but stamps the review when Airtable already holds the status" do
    decide!(:manually_passed)
    record = FakeAirtableRecord.new(fields: { "integrity_status" => "manually_passed" })

    assert_not stub_airtable_record(record) { perform }

    assert_empty record.saved_fields
    assert @review.reload.airtable_synced_at > @integrity.updated_at
  end

  test "skips a review whose integrity has not moved since the last sync" do
    @review.update_column(:airtable_synced_at, 1.minute.from_now)

    assert_not stub_airtable_record(->(_) { flunk "Airtable should not be called" }) { perform }
  end

  test "skips a review that was never synced" do
    decide!(:deducted, deduction_minutes: 30)
    @review.update_column(:airtable_synced_at, nil)

    assert_not stub_airtable_record(->(_) { flunk "Airtable should not be called" }) { perform }
  end

  test "skips a review whose ship event carries no integrity check" do
    @integrity.destroy!

    assert_not stub_airtable_record(->(_) { flunk "Airtable should not be called" }) { perform }
  end

  test "skips a review with no Airtable submission record" do
    decide!(:banned)

    assert_not stub_airtable_record(nil) { perform }
    assert_equal @synced_at.to_i, @review.reload.airtable_synced_at.to_i
  end

  test "leaves the sync marker alone when a full resync is still owed" do
    decide!(:banned)
    @review.update_column(:reviewed_at, Time.current)
    record = FakeAirtableRecord.new(fields: { "integrity_status" => "pending" })

    assert stub_airtable_record(record) { perform }

    assert_equal "banned", record["integrity_status"]
    assert_equal @synced_at.to_i, @review.reload.airtable_synced_at.to_i
  end

  test "a re-run writes nothing the second time" do
    decide!(:banned)
    record = FakeAirtableRecord.new(fields: { "integrity_status" => "pending" })

    stub_airtable_record(record) { perform }
    stub_airtable_record(record) { perform }

    assert_equal [ "integrity_status" ], record.saved_fields
  end

  private

  # Stands in for a Norairrecord record: only #[], #[]= and #save are exercised.
  class FakeAirtableRecord
    attr_reader :saved_fields

    def initialize(fields: {})
      @fields = fields
      @updated_keys = []
      @saved_fields = []
    end

    def [](field) = @fields[field]

    def []=(field, value)
      @fields[field] = value
      @updated_keys << field
    end

    def save
      @saved_fields.concat(@updated_keys)
      @updated_keys = []
      true
    end
  end

  def perform
    OneTime::SyncIntegrityStatusToAirtableJob.perform_now(@review.id)
  end

  def stub_airtable_record(record, &block)
    ::Certification::YswsAirtable.stub(:record_for, record, &block)
  end

  # Moves the check to a decided status, which bumps its updated_at past the
  # review's sync marker — the condition the job keys on.
  def decide!(status, deduction_minutes: nil)
    @integrity.skip_decision_cascade = true
    @integrity.update!(status: status, reviewer: @owner, deduction_minutes: deduction_minutes)
  end

  def create_project
    Project.create!(title: "Project #{SecureRandom.hex(4)}").tap do |project|
      Project::Membership.create!(project: project, user: @owner, role: :owner)
    end
  end

  def create_integrity(ship, status:)
    ::Certification::Integrity.create!(ship_event: ship, status: status)
  end

  def create_synced_ysws_review(project)
    ship = Post::ShipEvent.new(body: "ship it")
    ship.uploading_attachments = true
    ship.save!
    Post.create!(project: project, user: @owner, postable: ship)

    @synced_at = 1.day.ago
    ::Certification::Ysws.create!(
      user: @owner,
      project: project,
      post_ship_event: ship,
      original_minutes: 60,
      reviewer: @owner,
      reviewed_at: 2.days.ago,
      airtable_synced_at: @synced_at
    )
  end
end
