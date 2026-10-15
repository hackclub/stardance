require "test_helper"

module Notifications
  module Hardware
    class ReviewUndoneTest < ActiveSupport::TestCase
      setup do
        Flipper.enable(:hardware_flow)
        @owner = create_user(slack_id: "U_RU_OWNER", display_name: "ru_owner", verified: true)
        @reviewer = create_user(slack_id: "U_RU_REV", display_name: "ru_rev")
        @project = Project.create!(title: "Undone HW", hardware_stage: "design")
        Project::Membership.create!(project: @project, user: @owner, role: :owner)
        devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: "design")
        devlog.uploading_attachments = true
        devlog.save!
        Post.create!(project: @project, user: @owner, postable: devlog)
        @funding = @project.certification_funding_requests.create!(
          user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
        )
        @funding.update!(reviewer: @reviewer, status: :returned, feedback: "redo")
      end

      teardown { Flipper.disable(:hardware_flow) }

      test "is registered and high priority" do
        assert_includes Notifications::Registry.all, Notifications::Hardware::ReviewUndone
        assert_equal :high, Notifications::Hardware::ReviewUndone.default_priority
      end

      test "slack locals name the project and the review type" do
        notification = Notifications::Hardware::ReviewUndone.notify(
          recipient: @owner, actor: @reviewer, record: @funding
        )
        locals = notification.slack_locals

        assert_equal "Undone HW", locals[:project_title]
        assert_equal "funding request", locals[:review_type]
        assert locals[:project_url].present?
      end

      test "email subject names the project" do
        notification = Notifications::Hardware::ReviewUndone.notify(
          recipient: @owner, actor: @reviewer, record: @funding
        )
        assert_equal "The review of Undone HW was reopened", notification.email_subject
      end

      test "the owner slack template renders valid blocks" do
        notification = Notifications::Hardware::ReviewUndone.notify(
          recipient: @owner, actor: @reviewer, record: @funding
        )
        rendered = ApplicationController.renderer.new.render(
          template: "notifications/hardware/review_undone",
          formats: [ :slack_message ],
          locals: notification.slack_locals
        )
        assert JSON.parse(rendered)["blocks"].present?
      end
    end
  end
end
