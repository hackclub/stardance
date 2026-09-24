require "test_helper"

class OneTime::RefreshUnsubmittedHackatimeBansJobTest < ActiveSupport::TestCase
  include UserFactory
  include ActiveJob::TestHelper

  SYNC_JOB = Certification::YswsAirtableSyncJob

  setup do
    @hackatime_banned = create_user(slack_id: "u-ht-banned", display_name: "htbanned")
    @hackatime_banned.identities.create!(provider: "hackatime", uid: "ht-banned", access_token: "ht-secret")
    @already_banned = create_user(slack_id: "u-already-banned", display_name: "alreadybanned")
    @clean = create_user(slack_id: "u-clean", display_name: "clean")
    @clean.identities.create!(provider: "hackatime", uid: "ht-clean", access_token: "ht-secret")

    @hackatime_banned_review = completed_review(@hackatime_banned)
    @already_banned_review = completed_review(@already_banned)
    @clean_review = completed_review(@clean)
    @already_banned.update!(banned: true, banned_at: Time.current, banned_reason: "old ban")
  end

  test "a dry run reports who is behind a clean row and changes nothing" do
    result = with_hackatime { OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now }

    assert_equal [ @already_banned.id ], result.already_banned
    assert_equal [ @hackatime_banned.id ], result.hackatime_banned
    assert_not @hackatime_banned.reload.banned?
    assert_no_enqueued_jobs(only: SYNC_JOB)
  end

  test "the real run bans hackatime-banned users and resyncs every banned user's rows" do
    with_hackatime { OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now(dry_run: false) }

    assert @hackatime_banned.reload.banned?
    assert_not @clean.reload.banned?
    assert_enqueued_with(job: SYNC_JOB, args: [ @hackatime_banned_review.id ])
    assert_enqueued_with(job: SYNC_JOB, args: [ @already_banned_review.id ])
  end

  private

  def with_hackatime(&block)
    stats = ->(uid, **) { { banned: uid == "ht-banned", projects: {} } }
    HackatimeService.stub(:fetch_stats, stats, &block)
  end

  def completed_review(user)
    project = Project.create!(title: "Ship #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: user, postable: ship_event)
    Certification::Ysws.create!(user: user, project: project, post_ship_event: ship_event,
                                original_minutes: 120, reviewer: user, reviewed_at: Time.current)
  end
end
