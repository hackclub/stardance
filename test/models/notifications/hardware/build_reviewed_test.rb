require "test_helper"

module Notifications
  module Hardware
    class BuildReviewedTest < ActiveSupport::TestCase
      setup do
        Flipper.enable(:hardware_flow)
        @owner = create_user(slack_id: "U_BR_OWNER", display_name: "br_owner")
        @reviewer = create_user(slack_id: "U_BR_REVIEWER", display_name: "br_reviewer")
        @project = hardware_project("Reflow oven controller")
      end

      teardown { Flipper.disable(:hardware_flow) }

      test "notifies the project owner when a build is approved" do
        review = ship_review(@project)

        assert_difference -> { @owner.notifications.count }, 1 do
          review.update!(reviewer: @reviewer, status: :approved)
        end

        notification = @owner.notifications.order(:id).last
        assert_equal "Notifications::Hardware::BuildReviewed", notification.type
        assert_equal review, notification.record
        assert_equal @reviewer, notification.actor
      end

      test "notifies the project owner when a build is returned" do
        review = ship_review(@project)

        assert_difference -> { @owner.notifications.count }, 1 do
          review.update!(reviewer: @reviewer, status: :returned, feedback: "Show the enclosure closing.")
        end

        assert_equal "Notifications::Hardware::BuildReviewed",
                     @owner.notifications.order(:id).last.type
      end

      test "does not notify while the review is still pending" do
        assert_no_difference -> { @owner.notifications.count } do
          ship_review(@project)
        end
      end

      # Software verdicts keep the direct Slack DM, whose approval copy sends the
      # project off to voting. Routing them here would be wrong twice over.
      test "does not use this notification for a software project" do
        software = Project.create!(title: "Static site generator")
        Project::Membership.create!(project: software, user: @owner, role: :owner)

        assert_no_difference -> { @owner.notifications.count } do
          ship_review(software).update!(reviewer: @reviewer, status: :approved)
        end
      end

      test "notifies an owner who has no Slack account" do
        slackless = User.create!(email: "br_slackless@example.test", display_name: "br_slackless")
        project = hardware_project("Split keyboard", owner: slackless)

        assert_difference -> { slackless.notifications.count }, 1 do
          ship_review(project).update!(reviewer: @reviewer, status: :returned, feedback: "Needs a build log.")
        end
      end

      test "email subject names the project and the outcome" do
        review = ship_review(@project)
        review.update!(reviewer: @reviewer, status: :approved)

        notification = @owner.notifications.order(:id).last
        assert_equal "Reflow oven controller was approved", notification.email_subject

        review.update_columns(status: ::Certification::Ship.statuses[:returned])
        assert_equal "Reflow oven controller needs changes", notification.reload.email_subject
      end

      test "slack locals carry the verdict, reviewer and feedback" do
        review = ship_review(@project)
        review.update!(reviewer: @reviewer, status: :returned, feedback: "Show the enclosure closing.")

        locals = @owner.notifications.order(:id).last.slack_locals

        assert_equal "Reflow oven controller", locals[:project_title]
        assert_equal false, locals[:approved]
        assert_equal "Show the enclosure closing.", locals[:feedback]
        assert_equal "br_reviewer", locals[:reviewer_name]
        assert locals[:project_url].present?
      end

      # A broken notification backend must not cost the builder their verdict.
      test "the verdict still lands when notifying fails" do
        review = ship_review(@project)
        exploding = ->(**) { raise "notification backend down" }

        Notifications::Hardware::BuildReviewed.stub(:notify, exploding) do
          review.update!(reviewer: @reviewer, status: :approved)
        end

        assert_equal "approved", review.reload.status
      end

      test "is registered and high priority" do
        assert_includes Notifications::Registry.all, Notifications::Hardware::BuildReviewed
        assert_equal :high, Notifications::Hardware::BuildReviewed.default_priority
      end

      private

      def hardware_project(title, stage: "build", owner: @owner)
        project = Project.create!(title: title, hardware_stage: stage)
        Project::Membership.create!(project: project, user: owner, role: :owner)
        project
      end

      def ship_review(project)
        ::Certification::Ship.create!(project: project, status: :pending)
      end
    end
  end
end
