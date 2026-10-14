require "test_helper"

# A demo link often doesn't exist yet at the design/funding stage, so it must
# NOT gate a funding request - but it stays required to ship. These tests pin
# that split between #funding_info_complete? and #info_complete?.
class ProjectFundingInfoRequirementTest < ActiveSupport::TestCase
  # 1x1 PNG so the banner requirement (banner.attached?) is satisfied with a
  # real, processable image.
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @owner = create_user(slack_id: "U_FUNDING_INFO", display_name: "fundinginfo", verified: true)
    @project = Project.create!(title: "Design build", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)

    # Everything the project-info gate wants, except a demo link.
    @project.assign_attributes(
      description: "A neat hardware build",
      repo_url: "https://github.com/example/project",
      readme_url: "https://raw.githubusercontent.com/example/project/main/README.md",
      ai_declaration: "None"
    )
    @project.banner.attach(io: StringIO.new(PIXEL_PNG), filename: "banner.png", content_type: "image/png")
  end

  # url_reachable? (readme reachability) and GitRepoService.is_cloneable? (repo
  # cloneable) both hit the network; stub them so the checks stay hermetic.
  def with_reachable_and_cloneable
    @project.stub(:url_reachable?, true) do
      GitRepoService.stub(:is_cloneable?, true) do
        yield
      end
    end
  end

  test "demo_url is excluded from the funding gate but kept in the ship gate" do
    assert_includes Project::INFO_REQUIREMENT_KEYS, :demo_url
    assert_includes Project::INFO_REQUIREMENT_KEYS, :demo_url_reachable
    refute_includes Project::FUNDING_INFO_REQUIREMENT_KEYS, :demo_url
    refute_includes Project::FUNDING_INFO_REQUIREMENT_KEYS, :demo_url_reachable
  end

  test "a project with no demo_url is funding-complete but not info-complete" do
    assert @project.demo_url.blank?, "guard: demo_url should be blank for this case"

    with_reachable_and_cloneable do
      assert @project.funding_info_complete?,
        "funding gate should pass without a demo link"
      refute @project.info_complete?,
        "ship info gate should still fail without a demo link"

      demo_req = @project.shipping_requirements.find { |r| r[:key] == :demo_url }
      refute demo_req[:passed], "demo_url requirement should be unmet"

      assert_empty @project.incomplete_info_fields,
        "no info fields should be flagged red while designing (demo excluded)"
    end
  end

  test "incomplete_info_fields flags the demo link only once building" do
    assert @project.demo_url.blank?

    with_reachable_and_cloneable do
      refute_includes @project.incomplete_info_fields, :demo_url,
        "design-stage form must not flag the demo link red"

      @project.hardware_stage = "build"
      assert_includes @project.incomplete_info_fields, :demo_url,
        "build-stage form should flag the missing demo link"
    end
  end

  test "adding a demo_url makes the project info-complete too" do
    @project.demo_url = "https://example.com/demo"

    with_reachable_and_cloneable do
      assert @project.funding_info_complete?
      assert @project.info_complete?
    end
  end

  test "stage_info_complete? drops the demo requirement only at the design stage" do
    assert @project.demo_url.blank?, "guard: demo_url should be blank for this case"

    with_reachable_and_cloneable do
      assert @project.design_stage?, "guard: project starts in the design stage"
      assert @project.stage_info_complete?,
        "design-stage info should be complete without a demo link"

      @project.hardware_stage = "build"
      refute @project.stage_info_complete?,
        "build-stage info should require a demo link again"
    end
  end

  test "info_blocker_message never nags about a demo at the design stage" do
    assert @project.demo_url.blank?
    demo_label = @project.shipping_requirements.find { |r| r[:key] == :demo_url }[:label]

    with_reachable_and_cloneable do
      assert_nil @project.info_blocker_message,
        "design-stage builder has no outstanding (non-demo) info blocker"

      @project.hardware_stage = "build"
      assert_equal demo_label, @project.info_blocker_message,
        "build-stage builder is blocked on the demo link"
    end
  end
end
