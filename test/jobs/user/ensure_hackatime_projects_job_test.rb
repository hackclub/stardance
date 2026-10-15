require "test_helper"

class User::EnsureHackatimeProjectsJobTest < ActiveJob::TestCase
  setup do
    @user = create_user(slack_id: "U_UEHP_USER", display_name: "uehp_user")
    @other = create_user(slack_id: "U_UEHP_OTHER", display_name: "uehp_other")

    # fetch_stats is stubbed while linking so the after_create_commit sync on
    # User::Identity doesn't reach the network.
    HackatimeService.stub(:fetch_stats, nil) do
      @user.identities.create!(provider: "hackatime", uid: "ht-uehp-user", access_token: "user-token")
    end
  end

  def hardware_project(title, stage: "design", members: [])
    project = Project.create!(title: title)
    project.memberships.create!(user: @user, role: :owner)
    members.each { |member| project.memberships.create!(user: member, role: :contributor) }
    project.update!(hardware_stage: stage)
    project
  end

  # Building the fixtures turns projects hardware, which enqueues seeding jobs of
  # its own, so only what the block enqueues counts.
  def seeding_jobs_enqueued_by
    clear_enqueued_jobs
    yield
    enqueued_jobs.select { |job| job["job_class"] == "Project::EnsureHackatimeProjectsJob" }
                 .map { |job| job["arguments"].first }
  end

  test "enqueues seeding for a hardware project the member has no Hackatime project for" do
    project = hardware_project("Nebula macropad")

    seeded = seeding_jobs_enqueued_by { User::EnsureHackatimeProjectsJob.perform_now(@user.id) }

    assert_equal [ project.id ], seeded
  end

  test "ignores software projects" do
    Project.create!(title: "Signal lamp").memberships.create!(user: @user, role: :owner)

    seeded = seeding_jobs_enqueued_by { User::EnsureHackatimeProjectsJob.perform_now(@user.id) }

    assert_empty seeded
  end

  test "ignores hardware projects already linked for this member" do
    project = hardware_project("Orbital weather station", stage: "build")
    User::HackatimeProject.create!(user: @user, project: project, name: project.title)

    seeded = seeding_jobs_enqueued_by { User::EnsureHackatimeProjectsJob.perform_now(@user.id) }

    assert_empty seeded
  end

  # Each member records their own Lapse time, so a co-member's link doesn't cover
  # this one. This also guards the NOT IN / NULL trap: the unlinked Hackatime
  # project below puts a nil project_id in the subquery, which would otherwise
  # make the scope return nothing at all.
  test "enqueues seeding when only another member holds the link" do
    project = hardware_project("Rover chassis", stage: "build", members: [ @other ])
    User::HackatimeProject.create!(user: @other, project: project, name: project.title)
    User::HackatimeProject.create!(user: @user, name: "unrelated-key")

    seeded = seeding_jobs_enqueued_by { User::EnsureHackatimeProjectsJob.perform_now(@user.id) }

    assert_equal [ project.id ], seeded
  end

  test "does nothing without a Hackatime access token" do
    hardware_project("Desk plotter")
    tokenless = create_user(slack_id: "U_UEHP_NONE", display_name: "uehp_none")
    Project.create!(title: "Reflow hotplate").memberships.create!(user: tokenless, role: :owner)
    Project.find_by(title: "Reflow hotplate").update!(hardware_stage: "design")

    seeded = seeding_jobs_enqueued_by { User::EnsureHackatimeProjectsJob.perform_now(tokenless.id) }

    assert_empty seeded
  end

  test "linking Hackatime enqueues the fan-out for the member" do
    linker = create_user(slack_id: "U_UEHP_LINK", display_name: "uehp_link")

    assert_enqueued_with(job: User::EnsureHackatimeProjectsJob, args: [ linker.id ]) do
      HackatimeService.stub(:fetch_stats, nil) do
        linker.identities.create!(provider: "hackatime", uid: "ht-uehp-link", access_token: "link-token")
      end
    end
  end

  test "re-linking with a fresh token enqueues the fan-out again" do
    identity = @user.hackatime_identity

    assert_enqueued_with(job: User::EnsureHackatimeProjectsJob, args: [ @user.id ]) do
      HackatimeService.stub(:fetch_stats, nil) do
        identity.update!(access_token: "rotated-token")
      end
    end
  end
end
