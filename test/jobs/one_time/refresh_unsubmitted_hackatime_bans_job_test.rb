require "test_helper"

class OneTime::RefreshUnsubmittedHackatimeBansJobTest < ActiveSupport::TestCase
  include UserFactory
  include ActiveJob::TestHelper

  SYNC_JOB = Certification::YswsAirtableSyncJob

  setup do
    @hackatime_banned = linked_user("htbanned", "101")
    @clean = linked_user("clean", "102")
    @missing = linked_user("missing", "103")
    @unlinked = create_user(slack_id: "u-unlinked", display_name: "unlinked")
    @already_banned = create_user(slack_id: "u-already-banned", display_name: "alreadybanned")

    @reviews = [ @hackatime_banned, @clean, @missing, @unlinked, @already_banned ].index_with { |user| completed_review(user) }
    @already_banned.update!(banned: true, banned_at: Time.current, banned_reason: "old ban")
  end

  test "a dry run sorts everyone into a group and changes nothing" do
    result = with_trust_levels { OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now }

    assert_equal [ @already_banned.id ], result.already_banned
    assert_equal [ @hackatime_banned.id ], result.hackatime_banned
    assert_equal [ @unlinked.id ], result.no_hackatime
    assert_equal [ @missing.id ], result.unknown
    assert_not @hackatime_banned.reload.banned?
    assert_no_enqueued_jobs(only: SYNC_JOB)
  end

  test "the real run bans hackatime-banned users and resyncs every banned user's rows" do
    with_trust_levels { OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now(dry_run: false) }

    assert_equal User::HackatimeSync::HACKATIME_BAN_REASON, @hackatime_banned.reload.banned_reason
    assert_not @clean.reload.banned?
    assert_enqueued_with(job: SYNC_JOB, args: [ @reviews[@hackatime_banned].id ])
    assert_enqueued_with(job: SYNC_JOB, args: [ @reviews[@already_banned].id ])
  end

  test "a failed lookup leaves that batch unknown and bans nobody" do
    result = HackatimeService.stub(:fetch_trust_levels, nil) do
      OneTime::RefreshUnsubmittedHackatimeBansJob.perform_now(dry_run: false)
    end

    assert_equal [ @hackatime_banned.id, @clean.id, @missing.id ].sort, result.unknown.sort
    assert_not @hackatime_banned.reload.banned?
  end

  private

  def with_trust_levels(&block)
    HackatimeService.stub(:fetch_trust_levels, { "101" => "red", "102" => "green" }, &block)
  end

  def linked_user(name, uid)
    user = create_user(slack_id: "u-#{name}", display_name: name)
    user.identities.create!(provider: "hackatime", uid: uid, access_token: "ht-secret")
    user
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
