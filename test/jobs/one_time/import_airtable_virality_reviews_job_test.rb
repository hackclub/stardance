require "test_helper"

class OneTime::ImportAirtableViralityReviewsJobTest < ActiveSupport::TestCase
  setup do
    @mention = project_mentions(:virality_pending)
    @second = project_mentions(:virality_second)
    @rows = [
      { "id" => @mention.id, "project_id" => @mention.project_id, "review_status" => "approved", "threshold" => "Great",
        "platform" => "github", "metric_name" => "stars", "metric_value" => 120.0, "reviewer_notes" => "Well done! :)",
        "internal_notes" => "dmd for readme", "review_checklist" => [ "Hits threshold", "Original work", "Organic engagement" ] },
      { "id" => @second.id, "project_id" => @second.project_id, "review_status" => "on hold", "internal_notes" => "fraud?" },
      { "id" => 0, "project_id" => 1, "review_status" => "rejected" }
    ]
  end

  test "dry run reports the plan and writes nothing" do
    summary = run_job
    assert_equal({ proposed: [ @mention.id ], held: [ @second.id ], unmatched: [ 0 ] }, summary)
    assert_nil @mention.reload.proposed_action
    assert_nil @second.reload.on_hold_at
  end

  test "imports verdicts as proposals without approving or paying anything" do
    assert_no_difference -> { LedgerEntry.count } do
      run_job(dry_run: false)
    end

    @mention.reload
    assert_equal :pending, @mention.status
    assert_equal [ "approve", "great" ], [ @mention.proposed_action, @mention.proposed_tier ]
    assert_equal [ "GitHub", "stars", 120 ], [ @mention.platform, @mention.metric_name, @mention.metric_value ]
    assert_equal "Well done! :)", @mention.reviewer_notes
    assert_equal "dmd for readme", @mention.internal_notes
    assert_equal [ "Original work", "Organic engagement" ], @mention.review_checklist
    assert @mention.versions.exists?(event: "virality_airtable_import")

    @second.reload
    assert @second.on_hold_at?
    assert_nil @second.proposed_action
    assert_equal "fraud?", @second.internal_notes
  end

  test "running again changes nothing, and decided mentions are left alone" do
    run_job(dry_run: false)
    @second.update!(rejected_at: Time.current)

    summary = run_job(dry_run: false)
    assert_equal [ @mention.id ], summary[:unchanged]
    assert_equal [ @second.id ], summary[:already_reviewed]
  end

  private

  def run_job(**options)
    job = OneTime::ImportAirtableViralityReviewsJob.new
    job.stub(:rows, @rows) { job.perform(**options) }
  end
end
