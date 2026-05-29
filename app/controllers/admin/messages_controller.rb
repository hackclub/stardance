module Admin
  class MessagesController < Admin::ApplicationController
    def index
      authorize Message

      base_scope = Message.includes(:sent_by, :user).order(created_at: :desc)

      if params[:slack_id].present?
        @target_user = User.find_by(slack_id: params[:slack_id])
        if @target_user
          scoped_messages = base_scope.where(user: @target_user)
          @pagy, @messages = pagy(scoped_messages)
        else
          @pagy = nil
          @messages = Message.none
        end
      else
        @pagy, @messages = pagy(base_scope)
      end

      @user_count = params[:slack_id].present? ? (@target_user ? 1 : 0) : User.count
    end

    def create
      authorize Message

      content = params[:content].presence
      block_path = params[:block_path].presence

      if content.blank? && block_path.blank?
        redirect_to admin_messages_path(slack_id: params[:slack_id]), alert: "Either content or block path must be provided."
        return
      end

      if params[:slack_id].present?
        user = User.find_by(slack_id: params[:slack_id])
        unless user
          redirect_to admin_messages_path(slack_id: params[:slack_id]), alert: "User not found with that Slack ID."
          return
        end

        send_message_to_user(user, content, block_path)
        redirect_to admin_messages_path(slack_id: params[:slack_id]), notice: "Message sent to #{user.display_name || user.slack_id}."
      else
        recipients = User.all
        recipient_count = recipients.count

        expected_confirmation = "I know im about to mass dm #{recipient_count} users and cant revert this"
        if params[:confirmation] != expected_confirmation
          redirect_to admin_messages_path, alert: "Confirmation text did not match. Message not sent."
          return
        end

        ::PaperTrail::Version.create!(
          item_type: "User",
          item_id: current_user.id,
          event: "mass_dm_sent",
          whodunnit: current_user.id.to_s,
          object_changes: {
            recipient_count: recipient_count,
            content: content,
            block_path: block_path
          }.to_json
        )

        recipients.find_each do |user|
          send_message_to_user(user, content, block_path)
        end

        redirect_to admin_messages_path, notice: "Message sent to #{recipient_count} users."
      end
    end

    private

    def send_message_to_user(user, content, block_path)
      if block_path.present?
        SendSlackDmJob.perform_later(user.slack_id, content, blocks_path: block_path, sent_by_id: current_user.id)
      elsif content.present?
        SendSlackDmJob.perform_later(user.slack_id, content, sent_by_id: current_user.id)
      end
    end
  end
end
