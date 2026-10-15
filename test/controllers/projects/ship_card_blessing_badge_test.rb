# frozen_string_literal: true

require "test_helper"

class Projects::ShipCardBlessingBadgeTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(slack_id: "U_BLESSING_BADGE", display_name: "blessingbadge")

    @project = Project.create!(
      title: "Blessing Badge",
      description: "A project whose ship carries a payout blessing"
    )
    @project.memberships.create!(user: @owner, role: :owner)

    @ship = Post::ShipEvent.create!(
      body: "Ship it",
      uploading_attachments: true,
      certification_status: "approved",
      hours_at_ship: 1
    )
    Post.create!(project: @project, user: @owner, postable: @ship)
  end

  test "a cursed badge explains the halved payout" do
    @ship.update_columns(payout_blessing: "cursed")
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__latest-ship-status--info", text: "💀 Cursed", count: 1
    assert_select "[data-controller=tooltip][data-tooltip-title-value=?]", "Cursed", count: 1
    assert_select "[data-tooltip-message-value=?]",
                  "A curse for rushed voting — this ship's Stardust was halved.",
                  count: 1
  end

  test "a blessed badge explains the bonus" do
    @ship.update_columns(payout_blessing: "blessed")
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__latest-ship-status--info", text: "✨ Blessed", count: 1
    assert_select "[data-controller=tooltip][data-tooltip-title-value=?]", "Blessed", count: 1
    assert_select "[data-tooltip-message-value=?]",
                  "A blessing for thoughtful voting — this ship's Stardust includes a 20% bonus.",
                  count: 1
  end

  test "the badge is reachable by keyboard and labelled for screen readers" do
    @ship.update_columns(payout_blessing: "cursed")
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__latest-ship-status--info[tabindex=0][aria-label]", count: 1
  end

  test "an unrated ship shows no blessing badge" do
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_nil @ship.reload.payout_blessing
    assert_select ".project-show__latest-ship-status--info", count: 0
  end
end
