require "test_helper"

module Notifications
  module Hardware
    class FundingRequestReviewedTest < ActiveSupport::TestCase
      HCB_GRANT_RESPONSE = { "id" => "test_grant_notify" }.freeze

      setup do
        Flipper.enable(:hardware_flow)
        @owner = create_user(slack_id: "U_FRR_OWNER", display_name: "frr_owner", verified: true)
        @reviewer = create_user(slack_id: "U_FRR_REVIEWER", display_name: "frr_reviewer")

        @project = Project.create!(title: "Ferrofluid display", hardware_stage: "design")
        Project::Membership.create!(project: @project, user: @owner, role: :owner)
        devlog = Post::Devlog.new(body: "initial log", duration_seconds: 3600, phase: "design")
        devlog.uploading_attachments = true
        devlog.save!
        Post.create!(project: @project, user: @owner, postable: devlog)
      end

      def funding_request
        @project.certification_funding_requests.create!(
          user: @owner, complexity_tier: 2, requested_amount_cents: 6_000, status: :pending
        )
      end

      def approve!(request)
        HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
          request.update!(reviewer: @reviewer, status: :approved)
        end
      end

      test "notifies the project owner when a request is approved" do
        request = funding_request

        assert_difference -> { @owner.notifications.count }, 1 do
          approve!(request)
        end

        notification = @owner.notifications.order(:id).last
        assert_equal "Notifications::Hardware::FundingRequestReviewed", notification.type
        assert_equal request, notification.record
        assert_equal @reviewer, notification.actor
      end

      test "notifies the project owner when a request is returned" do
        request = funding_request

        assert_difference -> { @owner.notifications.count }, 1 do
          request.update!(reviewer: @reviewer, status: :returned, feedback: "Add the pump to the BOM.")
        end

        assert_equal "Notifications::Hardware::FundingRequestReviewed",
                     @owner.notifications.order(:id).last.type
      end

      test "does not notify while the request is still pending" do
        assert_no_difference -> { @owner.notifications.count } do
          funding_request
        end
      end

      # The old implementation DM'd Slack directly and returned early without a
      # slack_id, so builders who never linked Slack heard nothing at all.
      test "notifies an owner who has no Slack account" do
        slackless = User.create!(email: "slackless@example.test", display_name: "frr_slackless",
                                 verification_status: :verified, ysws_eligible: true)
        project = Project.create!(title: "Cassette synth", hardware_stage: "design")
        Project::Membership.create!(project: project, user: slackless, role: :owner)
        devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: "design")
        devlog.uploading_attachments = true
        devlog.save!
        Post.create!(project: project, user: slackless, postable: devlog)
        request = project.certification_funding_requests.create!(
          user: slackless, complexity_tier: 1, requested_amount_cents: 2_000, status: :pending
        )

        assert_difference -> { slackless.notifications.count }, 1 do
          request.update!(reviewer: @reviewer, status: :returned, feedback: "Needs a parts list.")
        end
      end

      test "email subject names the project and the outcome" do
        request = funding_request
        approve!(request)

        notification = @owner.notifications.order(:id).last
        assert_equal "Ferrofluid display was approved for funding", notification.email_subject

        request.update_columns(status: Certification::FundingRequest.statuses[:returned])
        assert_equal "Ferrofluid display needs changes before funding",
                     notification.reload.email_subject
      end

      test "slack locals carry the verdict, amount and feedback" do
        request = funding_request
        request.update!(reviewer: @reviewer, status: :returned, feedback: "Add the pump to the BOM.")

        locals = @owner.notifications.order(:id).last.slack_locals

        assert_equal "Ferrofluid display", locals[:project_title]
        assert_equal false, locals[:approved]
        assert_equal "Add the pump to the BOM.", locals[:feedback]
        assert_equal "frr_reviewer", locals[:reviewer_name]
        assert locals[:project_url].present?
      end

      # A dead HCB token used to take the notification down with it: the grant
      # callback was declared first, and its raise stopped the rest of the chain.
      test "still notifies when issuing the HCB grant fails" do
        request = funding_request
        # HCBError is defined inside hcb_service.rb (Zeitwerk maps that file to
        # HCBService), so touch the service first or the constant may not exist.
        error_class = HCBService && HCBError
        exploding = ->(**) { raise error_class, "token refresh failed: invalid_grant" }

        assert_difference -> { @owner.notifications.count }, 1 do
          assert_raises(error_class) do
            HCBService.stub(:create_card_grant, exploding) do
              request.update!(reviewer: @reviewer, status: :approved)
            end
          end
        end

        assert_nil request.reload.hcb_grant_hashid
        assert_equal "approved", request.status
      end

      # And the reverse: a broken notification must not cost the builder a grant.
      test "still issues the grant when notifying fails" do
        request = funding_request
        exploding = ->(**) { raise "notification backend down" }

        Notifications::Hardware::FundingRequestReviewed.stub(:notify, exploding) do
          approve!(request)
        end

        assert_equal "test_grant_notify", request.reload.hcb_grant_hashid
      end

      test "is registered and high priority" do
        assert_includes Notifications::Registry.all, Notifications::Hardware::FundingRequestReviewed
        assert_equal :high, Notifications::Hardware::FundingRequestReviewed.default_priority
      end
    end
  end
end
