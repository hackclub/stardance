require "test_helper"

class CommentPolicyTest < ActiveSupport::TestCase
  setup do
    @author    = create_user(slack_id: "U_COMMENT_AUTHOR", display_name: "ca")
    @commenter = create_user(slack_id: "U_COMMENT_USER",   display_name: "cu")
    @comment = Comment.new(user: @commenter)
  end

  test "create? is false for nil user" do
    refute CommentPolicy.new(nil, @comment).create?
  end

  test "create? is false for a logged-in but unverified user" do
    @commenter.update!(verification_status: "needs_submission")
    refute CommentPolicy.new(@commenter, @comment).create?
  end

  test "create? is true once the user is verified" do
    @commenter.update!(verification_status: "verified")
    assert CommentPolicy.new(@commenter, @comment).create?
  end

  test "destroy? still allowed for owner regardless of verification" do
    @commenter.update!(verification_status: "needs_submission")
    assert CommentPolicy.new(@commenter, @comment).destroy?
  end
end
