require "test_helper"

class PostVisibilityTest < ActiveSupport::TestCase
  setup do
    @verified   = create_user(slack_id: "U_POST_VER", display_name: "pver")
    @verified.update!(verification_status: "verified")

    @unverified = create_user(slack_id: "U_POST_UNV", display_name: "punv")
    @unverified.update!(verification_status: "needs_submission")

    @admin = create_user(slack_id: "U_POST_ADMIN", display_name: "padmin")
    @admin.update!(granted_roles: [ "admin" ])

    @project = Project.create!(title: "vp", description: "d")
    @project.memberships.create!(user: @verified, role: :owner)
    @project.memberships.create!(user: @unverified, role: :contributor)

    @verified_fire   = Post::FireEvent.create!(body: "ver fire")
    @verified_post   = Post.create!(project: @project, user: @verified, postable: @verified_fire)

    @unverified_fire = Post::FireEvent.create!(body: "unv fire")
    @unverified_post = Post.create!(project: @project, user: @unverified, postable: @unverified_fire)
  end

  test "logged-out viewer only sees verified-author posts" do
    visible_ids = Post.visible_to(nil).pluck(:id)
    assert_includes visible_ids, @verified_post.id
    refute_includes visible_ids, @unverified_post.id
  end

  test "non-admin viewer doesn't see unverified-author posts" do
    other = create_user(slack_id: "U_POST_OTHER", display_name: "pother")
    other.update!(verification_status: "verified")

    visible_ids = Post.visible_to(other).pluck(:id)
    assert_includes visible_ids, @verified_post.id
    refute_includes visible_ids, @unverified_post.id
  end

  test "unverified viewer still sees their own posts" do
    visible_ids = Post.visible_to(@unverified).pluck(:id)
    assert_includes visible_ids, @unverified_post.id
  end

  test "admin sees every post regardless of verification" do
    visible_ids = Post.visible_to(@admin).pluck(:id)
    assert_includes visible_ids, @verified_post.id
    assert_includes visible_ids, @unverified_post.id
  end
end
