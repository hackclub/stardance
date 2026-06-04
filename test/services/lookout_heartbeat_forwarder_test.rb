require "test_helper"

class LookoutHeartbeatForwarderTest < ActiveSupport::TestCase
  setup do
    @user = create_user(slack_id: "U_FWDR", display_name: "fwdr")
    # A Hackatime identity with a token is required to forward. Stub fetch_stats
    # so the after_create_commit sync doesn't hit the network.
    HackatimeService.stub(:fetch_stats, nil) do
      @user.identities.create!(provider: "hackatime", uid: "ht-fwdr", access_token: "ht-secret")
    end
    @project = Project.create!(title: "Robot arm", hardware_stage: "build")
    @session = @project.lookout_sessions.create!(user: @user, token: "tok-fwdr", status: "stopped")
  end

  test "sends Lookout heartbeats, links the project, and reports how many on success" do
    captured = nil
    push = ->(api_key:, heartbeats:) { captured = { key: api_key, beats: heartbeats }; true }

    result =
      HackatimeService.stub(:fetch_api_key, "ht-api-key") do
        LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z", "2026-06-03T10:01:00Z" ] }) do
          HackatimeService.stub(:push_heartbeats, push) do
            LookoutHeartbeatForwarder.call(@session, project_name: "Chosen Project")
          end
        end
      end

    assert result.ok?
    assert_nil result.error
    assert_equal 2, result.count

    assert_equal "ht-api-key", captured[:key]
    beat = captured[:beats].first
    assert_equal "Chosen Project", beat[:project]
    assert_equal "Lookout", beat[:editor]
    assert_equal "Lookout", beat[:language]
    assert_equal @session.token, beat[:entity]
    assert_equal Time.utc(2026, 6, 3, 10, 0, 0).to_i, beat[:time]

    link = User::HackatimeProject.find_by(user: @user, name: "Chosen Project")
    assert_equal @project.id, link&.project_id
  end

  test "falls back to the project's recorder name when no destination is given" do
    captured = nil
    push = ->(api_key:, heartbeats:) { captured = heartbeats; true }

    HackatimeService.stub(:fetch_api_key, "ht-api-key") do
      LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z" ] }) do
        HackatimeService.stub(:push_heartbeats, push) do
          LookoutHeartbeatForwarder.call(@session)
        end
      end
    end

    assert_equal @project.hackatime_recorder_name, captured.first[:project]
  end

  test "fails with a link-your-account message when there's no Hackatime identity" do
    other = create_user(slack_id: "U_FWDR_NOHT", display_name: "fwdr_noht")
    session = @project.lookout_sessions.create!(user: other, token: "tok-fwdr-noht", status: "stopped")

    pushed = false
    result =
      HackatimeService.stub(:push_heartbeats, ->(**) { pushed = true }) do
        LookoutHeartbeatForwarder.call(session, project_name: "Anything")
      end

    assert_not result.ok?
    assert_equal 0, result.count
    assert_match(/link your hackatime account/i, result.error)
    assert_not pushed, "must not push when the user has no Hackatime account"
  end

  test "fails when the Hackatime API key can't be fetched" do
    result =
      HackatimeService.stub(:fetch_api_key, nil) do
        LookoutHeartbeatForwarder.call(@session, project_name: "Chosen Project")
      end

    assert_not result.ok?
    assert_match(/authorize/i, result.error)
  end

  test "fails when Lookout has no tracked time to send" do
    result =
      HackatimeService.stub(:fetch_api_key, "ht-api-key") do
        LookoutService.stub(:fetch_timings, { "timestamps" => [] }) do
          LookoutHeartbeatForwarder.call(@session, project_name: "Chosen Project")
        end
      end

    assert_not result.ok?
    assert_match(/tracked time/i, result.error)
  end

  test "fails and does not link the project when Hackatime rejects the push" do
    result =
      HackatimeService.stub(:fetch_api_key, "ht-api-key") do
        LookoutService.stub(:fetch_timings, { "timestamps" => [ "2026-06-03T10:00:00Z" ] }) do
          HackatimeService.stub(:push_heartbeats, false) do
            LookoutHeartbeatForwarder.call(@session, project_name: "Rejected Project")
          end
        end
      end

    assert_not result.ok?
    assert_match(/didn't accept/i, result.error)
    assert_nil User::HackatimeProject.find_by(user: @user, name: "Rejected Project")
  end
end
