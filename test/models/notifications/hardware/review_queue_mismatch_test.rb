require "test_helper"

module Notifications
  module Hardware
    # Every notification type needs three view files: the inbox partial, the
    # Slack blocks, and the mailer pair. A missing one is invisible until it
    # fires - the inbox 500s, and the mailer is rescued so the email just never
    # arrives - so each surface is rendered here.
    class ReviewQueueMismatchTest < ActionDispatch::IntegrationTest
      setup do
        Flipper.enable(:hardware_flow)
        @owner = create_user(slack_id: "U_RQM_OWNER", display_name: "rqm-owner", verified: true)
        @reviewer = create_user(slack_id: "U_RQM_REV", display_name: "rqm-rev")
        @reviewer.grant_role!(:admin)

        @project = Project.create!(title: "Cassette synth", hardware_stage: "design")
        Project::Membership.create!(project: @project, user: @owner, role: :owner)
        devlog = Post::Devlog.new(body: "initial log", duration_seconds: 3600, phase: "design")
        devlog.uploading_attachments = true
        devlog.save!
        Post.create!(project: @project, user: @owner, postable: devlog)

        @request = @project.certification_funding_requests.create!(
          user: @owner, complexity_tier: 2, requested_amount_cents: 6_000, status: :pending
        )
      end

      teardown { Flipper.disable(:hardware_flow) }

      def flag!
        @request.flag_queue_mismatch!(reviewer: @reviewer, reason: "This looks finished already")
        @owner.notifications.order(:id).last
      end

      test "is registered and high priority" do
        assert_includes Notifications::Registry.all, Notifications::Hardware::ReviewQueueMismatch
        assert_equal :high, Notifications::Hardware::ReviewQueueMismatch.default_priority
      end

      test "flagging notifies the owner" do
        assert_difference -> { @owner.notifications.count }, 1 do
          flag!
        end
        assert_equal "Notifications::Hardware::ReviewQueueMismatch",
                     @owner.notifications.order(:id).last.type
      end

      test "email subject names the project" do
        assert_equal "Cassette synth needs a quick answer before it can be reviewed",
                     flag!.email_subject
      end

      test "slack locals carry both queues and the reviewer's note" do
        locals = flag!.slack_locals

        assert_equal "Cassette synth", locals[:project_title]
        assert_equal "design funding", locals[:flagged_queue]
        assert_equal "build certification", locals[:suggested_queue]
        assert_equal "rqm-rev", locals[:reviewer_name]
        assert_equal "This looks finished already", locals[:reason]
        assert locals[:project_url].present?
      end

      # The bug this file exists for: no inbox partial meant /my/notifications
      # raised MissingTemplate for anyone holding one of these.
      test "the inbox row renders" do
        flag!
        sign_in @owner

        get my_notifications_path

        assert_response :success
        assert_select ".notifications-item__title", text: /question about your submission/
        assert_select ".notifications-item__title a", text: "Cassette synth"
      end

      test "the email renders in both formats" do
        notification = flag!

        mail = NotificationMailer.notification(notification.id)
        body = mail.body.encoded

        assert_match "Cassette synth", body
        assert_match "This looks finished already", body
        assert_match "already built", body, "should name the direction the reviewer suggested"
      end
    end
  end
end
