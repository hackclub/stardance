require "test_helper"

class Admin::ShipFunnelTest < ActiveSupport::TestCase
  include UserFactory

  setup { @user = create_user(slack_id: "u-ship-funnel", display_name: "shipfunnel") }

  test "a ship waiting on Shipwrights flows from shipped into the Shipwrights queue" do
    ship(hours: 3)

    assert_link "Shipped", "Shipwrights review", hours: 3, ships: 1
    assert_link "Shipwrights review", "Waiting on Shipwrights", hours: 3, ships: 1
  end

  test "a banned user's ship leaves as fraud, whatever stage it reached" do
    ship(hours: 2, status: "approved")
    @user.update_column(:banned, true)

    assert_link "Shipped", "Fraud", hours: 2, ships: 1
    assert_no_link "Shipped", "Shipwrights review"
  end

  test "an approved reship that skipped Shipwrights enters GOI through the reship node" do
    ship(hours: 4, status: "approved")

    assert_link "Shipped", "Reship, skipped review", hours: 4, ships: 1
    assert_link "Reship, skipped review", "GOI review", hours: 4, ships: 1
    assert_link "GOI review", "Approved, no GOI review", hours: 4, ships: 1
  end

  test "the loops count ships with more than one GOI review" do
    event = ship(hours: 1, status: "approved")
    2.times { Certification::Ysws.create!(user: @user, project: event.post.project, post_ship_event: event, original_minutes: 60) }

    assert_equal 1, funnel[:loops][:goi_twice]
  end

  private

  def funnel
    @funnel ||= Certification::YswsAirtable.stub(:table, Struct.new(:rows) { def all(**) = rows }.new([])) do
      Admin::ShipFunnel.new.to_h
    end
  end

  def ship(hours:, status: "pending")
    project = Project.create!(title: "Funnel #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: event)
    event.update_columns(hours_at_ship: hours, certification_status: status)
    event
  end

  def link(source, target) = funnel[:links].find { |l| l[:kind] == "software" && l[:source] == source && l[:target] == target }

  def assert_link(source, target, hours:, ships:)
    found = link(source, target)
    assert found, "expected a #{source} → #{target} link in #{funnel[:links].map { |l| [ l[:source], l[:target] ] }}"
    assert_in_delta hours, found[:hours], 0.001
    assert_equal ships, found[:ships]
  end

  def assert_no_link(source, target) = assert_nil(link(source, target))
end
