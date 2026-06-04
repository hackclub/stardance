# frozen_string_literal: true

module Gorse::Feedbackable
  extend ActiveSupport::Concern

  def send_gorse_feedback_later(user:, item:, feedback_type:, value: 1, timestamp: Time.current, comment: nil)
    if Gorse.enabled?
      Gorse::SyncFeedbackJob.perform_later(
        user,
        item,
        feedback_type.to_s,
        value: value,
        timestamp: timestamp,
        comment: comment
      )
    end
  end
end
