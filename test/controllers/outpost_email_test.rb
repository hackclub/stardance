require "test_helper"

class OutpostEmailTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
    Flipper.enable(:outpost_email)
  end

  teardown { Flipper.disable(:outpost_email) }

  test "no email is sent when the outpost_email flag is disabled" do
    Flipper.disable(:outpost_email)
    sign_in @user

    assert_no_enqueued_emails { get "/outpost" }
    assert_nil @user.reload.outpost_email_sent_at
  end

  test "logged-in visitor to /outpost gets the email exactly once" do
    sign_in @user

    # The Slack channel add is temporarily disabled (see User#deliver_outpost_email!),
    # so only the email may be enqueued.
    assert_no_enqueued_jobs only: AddUserToOutpostChannelJob do
      assert_enqueued_email_with UserMailer, :outpost, args: [ @user ] do
        get "/outpost"
      end
    end
    assert_redirected_to guide_path(:outpost)
    assert_not_nil @user.reload.outpost_email_sent_at

    # A second visit must not enqueue another email.
    assert_no_enqueued_emails { get "/outpost" }
  end

  # Re-enable together with the AddUserToOutpostChannelJob trigger in
  # User#deliver_outpost_email!.
  # test "user without a slack_id still enqueues the channel add (job resolves the id via email)" do
  #   @user.update!(slack_id: nil)
  #   sign_in @user
  #
  #   assert_enqueued_with job: AddUserToOutpostChannelJob, args: [ @user.id ] do
  #     assert_enqueued_email_with UserMailer, :outpost, args: [ @user ] do
  #       get "/outpost"
  #     end
  #   end
  # end

  test "logged-out /outpost visit defers the email until sign in" do
    # Logged-out visitors are not redirected to the guide; they stay on the
    # landing page to sign up first.
    assert_no_enqueued_emails { get "/outpost" }
    assert_response :success
    assert_nil @user.reload.outpost_email_sent_at

    sign_in @user

    # First request once signed in flushes the pending email, exactly once.
    assert_enqueued_email_with UserMailer, :outpost, args: [ @user ] do
      get root_path
    end
    assert_not_nil @user.reload.outpost_email_sent_at

    assert_no_enqueued_emails { get root_path }
  end
end
