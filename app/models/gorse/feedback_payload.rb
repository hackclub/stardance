# frozen_string_literal: true

class Gorse::FeedbackPayload
  POSITIVE_TYPES = %w[like comment repost follow_project vote watch dwell].freeze
  READ_TYPES = %w[read open].freeze
  NEGATIVE_TYPES = %w[skip hide not_interested].freeze

  def initialize(user:, item:, feedback_type:, value: 1, timestamp: Time.current, comment: nil)
    @user = user
    @item = item
    @feedback_type = feedback_type.to_s
    @value = value
    @timestamp = timestamp
    @comment = comment
  end

  def to_h
    if user.present? && item.present? && gorse_item_id.present? && known_type?
      {
        FeedbackType: feedback_type,
        UserId: Gorse::Ids.user(user),
        ItemId: gorse_item_id,
        Value: value,
        Timestamp: timestamp.iso8601,
        Comment: comment.to_s
      }
    end
  end

  private
    attr_reader :user, :item, :feedback_type, :value, :timestamp, :comment

    def gorse_item_id
      case item
      when Post
        Gorse::Ids.post(item)
      when Project
        Gorse::Ids.project(item)
      end
    end

    def known_type?
      (POSITIVE_TYPES + READ_TYPES + NEGATIVE_TYPES).include?(feedback_type)
    end
end
