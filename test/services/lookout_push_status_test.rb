require "test_helper"

class LookoutPushStatusTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @project = projects(:one)
    @a = LookoutSession.create!(user: @user, project: @project, token: "tok-a",
                                status: "complete", duration_seconds: 600,
                                started_at: Time.utc(2026, 7, 15, 12))
    @b = LookoutSession.create!(user: @user, project: @project, token: "tok-b",
                                status: "complete", duration_seconds: 600,
                                started_at: Time.utc(2026, 7, 16, 12))
    Rails.cache.clear
  end

  # A session is "pushed" iff Hackatime holds a heartbeat whose entity is its
  # token, the exact fingerprint the forwarder stamps.
  test "flags only the sessions whose token appears as a Hackatime heartbeat entity" do
    identity = Struct.new(:access_token).new("oauth-tok")
    heartbeats = [ { "entity" => "tok-a", "project" => "Robot", "time" => 1 },
                   { "entity" => "unrelated", "project" => "Other", "time" => 2 } ]

    @user.stub(:hackatime_identity, identity) do
      HackatimeService.stub(:fetch_api_key, "key") do
        HackatimeService.stub(:fetch_heartbeats, ->(**) { heartbeats }) do
          pushed = LookoutPushStatus.pushed_tokens(user: @user)

          assert_includes pushed, "tok-a"
          assert_not_includes pushed, "tok-b"
        end
      end
    end
  end

  test "returns empty (all unpushed) and never calls Hackatime without a linked identity" do
    @user.stub(:hackatime_identity, nil) do
      HackatimeService.stub(:fetch_heartbeats, ->(**) { raise "should not reach Hackatime" }) do
        assert_empty LookoutPushStatus.pushed_tokens(user: @user)
      end
    end
  end

  test "treats an unreachable Hackatime as everything-unpushed instead of raising" do
    identity = Struct.new(:access_token).new("oauth-tok")
    @user.stub(:hackatime_identity, identity) do
      HackatimeService.stub(:fetch_api_key, "key") do
        HackatimeService.stub(:fetch_heartbeats, ->(**) { [] }) do
          assert_empty LookoutPushStatus.pushed_tokens(user: @user)
        end
      end
    end
  end
end
