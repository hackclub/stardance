# frozen_string_literal: true

class Gorse::SyncFeedbackJob < ApplicationJob
  queue_as :default

  def perform(user, item, feedback_type, value: 1, timestamp: Time.current, comment: nil)
    payload = Gorse::FeedbackPayload.new(
      user: user,
      item: item,
      feedback_type: feedback_type,
      value: value,
      timestamp: timestamp,
      comment: comment
    ).to_h

    Gorse::Client.new.insert_feedback(payload)
  end
end
