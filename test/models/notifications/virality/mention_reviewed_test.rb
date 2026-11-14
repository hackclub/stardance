require "test_helper"

module Notifications
  module Virality
    class MentionReviewedTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        @mention = project_mentions(:virality_pending)
        @project = @mention.project
        @project.update!(ship_status: "approved")
        @owner = users(:one)
        @project.memberships.find_by!(user: @owner).update!(role: :owner)
        @admin = users(:two)
        @admin.update!(granted_roles: [ "admin" ])
      end

      test "notifies the owner once an approval is processed" do
        decision = schedule

        assert_no_difference -> { reviewed_count } do
          refute decision.process!
        end
        assert_difference -> { reviewed_count }, 1 do
          apply(decision)
        end

        notification = reviewed.sole
        assert_equal decision, notification.record
        assert_equal @admin, notification.actor
        assert_equal "Your viral mention for #{@project.title} was approved", notification.email_subject
      end

      test "a stopped decision never notifies" do
        decision = schedule
        decision.cancel!(actor: @admin)

        assert_no_difference -> { reviewed_count } do
          travel_to(decision.process_at + 1.second) { ProcessViralityDecisionJob.perform_now(decision.id) }
        end
      end

      test "rejections and reversals notify with their own subject and the reviewer note" do
        apply(schedule(action: "reject", tier: nil, reason: "Below the Good threshold."))
        rejected = latest
        assert_equal "Your viral mention for #{@project.title} wasn't approved", rejected.email_subject
        assert_equal "Below the Good threshold.", rejected.preview_text

        apply(schedule(action: "reverse", tier: nil, reason: "Rejected by mistake."))
        assert_equal "Your viral mention for #{@project.title} is back in review", latest.email_subject
      end

      test "the decision still processes when notifying fails" do
        decision = schedule
        exploding = ->(**) { raise "notification backend down" }

        MentionReviewed.stub(:notify, exploding) { apply(decision) }

        assert_equal "processed", decision.reload.status
        assert_equal :approved, @mention.reload.status
      end

      test "slack locals drop a mention url that would break the link" do
        locals = apply(schedule).notification_locals
        assert_equal @mention.url, locals[:mention_url]
        assert_equal "good", locals[:tier]

        @mention.update_columns(url: "https://example.com/a|<!channel>")
        assert_nil @mention.reload.virality_decisions.last.notification_locals[:mention_url]
      end

      test "the slack message renders for every outcome" do
        decision = apply(schedule)
        %w[approve reject reverse].each do |action|
          rendered = ApplicationController.renderer.new.render(
            template: MentionReviewed.slack_template_path, formats: [ :slack_message ],
            locals: decision.notification_locals.merge(action: action)
          )
          assert JSON.parse(rendered)["blocks"].present?, "#{action} rendered no blocks"
        end
      end

      test "the inbox row and email render" do
        apply(schedule(reason: "Nice traction!"))
        sign_in @owner

        get my_notifications_path

        assert_response :success
        assert_select ".notifications-item__title", text: /viral mention/
        assert_select ".notifications-item__title a", text: @project.title

        body = NotificationMailer.notification(latest.id).body.encoded
        assert_match "Good", body
        assert_match "Nice traction!", body
        assert_match @mention.url, body
      end

      test "is registered and high priority" do
        assert_includes Notifications::Registry.all, MentionReviewed
        assert_equal :high, MentionReviewed.default_priority
      end

      private

      def schedule(**overrides)
        attributes = { action: "approve", tier: "good", reason: "Checked the public repository",
                       evidence: { "platform" => "GitHub", "metric_name" => "stars", "metric_value" => "25", "eligibility_confirmed" => "1" } }
        ViralityDecision.schedule!(mention: @mention.reload, reviewer: @admin, attributes: attributes.merge(overrides))
      end

      def apply(decision)
        travel_to(decision.process_at + 1.second) { assert decision.process! }
        decision
      end

      def reviewed = @owner.notifications.where(type: MentionReviewed.name)
      def reviewed_count = reviewed.count
      def latest = reviewed.order(:id).last
    end
  end
end
