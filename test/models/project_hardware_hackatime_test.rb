require "test_helper"

# The Hackatime project is seeded off the hardware transition rather than from
# any one controller, so these lock down when that transition is detected.
class ProjectHardwareHackatimeTest < ActiveJob::TestCase
  setup do
    @user = create_user(slack_id: "U_PHH", display_name: "phh")
    @project = Project.create!(title: "Rover")
    @project.memberships.create!(user: @user, role: :owner)
  end

  test "enqueues a seed when a software project switches to hardware" do
    assert_enqueued_with(job: Project::EnsureHackatimeProjectsJob, args: [ @project.id ]) do
      @project.update!(hardware_stage: "design")
    end
  end

  test "enqueues a seed for a project born hardware" do
    assert_enqueued_with(job: Project::EnsureHackatimeProjectsJob) do
      Project.create!(title: "Born hardware", hardware_stage: "design")
    end
  end

  test "does not re-seed when advancing design to build" do
    @project.update!(hardware_stage: "design")

    assert_no_enqueued_jobs(only: Project::EnsureHackatimeProjectsJob) do
      @project.advancing_via_funding_approval = true
      @project.update!(hardware_stage: "build")
    end
  end

  test "does not seed on an unrelated update to a hardware project" do
    @project.update!(hardware_stage: "design")

    assert_no_enqueued_jobs(only: Project::EnsureHackatimeProjectsJob) do
      @project.update!(description: "now with more wheels")
    end
  end

  test "does not seed for a software project" do
    assert_no_enqueued_jobs(only: Project::EnsureHackatimeProjectsJob) do
      Project.create!(title: "Pure software").update!(description: "still software")
    end
  end

  # Both create flows post a placeholder title, so the project is normally named
  # after it turns hardware. Seeding then would name the Hackatime project
  # "Untitled".
  test "does not seed while the project still has a placeholder title" do
    [ Project::DEFAULT_TITLE, Project::SETUP_DEFAULT_TITLE ].each do |placeholder|
      project = Project.create!(title: placeholder)
      project.memberships.create!(user: @user, role: :owner)

      assert_no_enqueued_jobs(only: Project::EnsureHackatimeProjectsJob) do
        project.update!(hardware_stage: "design")
      end
    end
  end

  test "seeds when a placeholder-titled hardware project is finally named" do
    project = Project.create!(title: Project::DEFAULT_TITLE)
    project.memberships.create!(user: @user, role: :owner)
    project.update!(hardware_stage: "design")

    assert_enqueued_with(job: Project::EnsureHackatimeProjectsJob, args: [ project.id ]) do
      project.update!(title: "Solar tracker")
    end
  end

  test "seeds the new name when an already-named hardware project is renamed" do
    @project.update!(hardware_stage: "design")

    assert_enqueued_with(job: Project::EnsureHackatimeProjectsJob, args: [ @project.id ]) do
      @project.update!(title: "Rover mk2")
    end
  end

  test "does not seed when a software project is renamed" do
    assert_no_enqueued_jobs(only: Project::EnsureHackatimeProjectsJob) do
      @project.update!(title: "Still software")
    end
  end

  test "enqueues a seed when someone joins an already-hardware project" do
    @project.update!(hardware_stage: "design")
    joiner = create_user(slack_id: "U_PHH_JOIN", display_name: "phh_join")

    assert_enqueued_with(job: Project::EnsureHackatimeProjectsJob, args: [ @project.id ]) do
      @project.memberships.create!(user: joiner, role: :contributor)
    end
  end
end
