module Notifications
  class ItemComponent < ViewComponent::Base
    delegate :inline_svg_tag, to: :helpers

    TYPE_ICONS = {
      "Notifications::NewFollower"                              => "person",
      "Notifications::ProjectFollowed"                          => "person",
      "Notifications::ProjectCommentReceived"                   => "comment",
      "Notifications::MentionReceived"                          => "comment",
      "Notifications::DevlogLiked"                              => "like",
      "Notifications::DevlogReposted"                           => "repost",
      "Notifications::DevlogQuoteReposted"                      => "repost",
      "Notifications::FollowedDevlogCreated"                    => "pencil",
      "Notifications::StardustBalanceChanged"                   => "sparkle",
      "Notifications::AchievementEarned"                        => "trophy",
      "Notifications::Payouts::ShipEventIssued"                 => "rocket",
      "Notifications::Payouts::VoteDeficitBlocked"              => "thumbs-up",
      "Notifications::Projects::SuperStar"                      => "star",
      "Notifications::Missions::SubmissionApproved"             => "check-circle",
      "Notifications::Missions::SubmissionRejected"             => "alert-triangle",
      "Notifications::Missions::SubmissionPendingForReviewer"   => "clipboard",
      "Notifications::ShopOrders::StatusChanged"                => "bag"
    }.freeze

    attr_reader :notification

    def initialize(notification:)
      @notification = notification
    end

    def li_classes
      [
        "notifications-item",
        # "New" highlight is driven by the unread state: opening the inbox marks
        # everything read, so a row is highlighted on the visit it arrives and
        # plain on every subsequent visit (reading == opening the page).
        ("notifications-item--unread" if notification.read_at.nil?),
        ("notifications-item--expandable" if expandable?)
      ].compact.join(" ")
    end

    # Clicking anywhere on an aggregated card toggles its expander (the Stimulus
    # controller ignores clicks that land on a real link inside the card).
    def card_data
      data = { notification_id: notification.id }
      if expandable?
        data[:controller] = "notification-actors"
        data[:action] = "click->notification-actors#toggle"
      end
      data
    end

    def time_text
      helpers.time_ago_in_words(notification.created_at) + " ago"
    end

    def type_icon_path
      name = TYPE_ICONS[notification.type] || "bell"
      "icons/notifications/#{name}.svg"
    end

    def avatar_actor
      notification.actor
    end

    # All actors behind an aggregated notification, for the expandable list.
    def aggregated_actors
      @aggregated_actors ||= notification.aggregated_actors
    end

    # Whether the card can expand to reveal who else is behind the aggregate.
    def expandable?
      notification.group_count.to_i > 1 && aggregated_actors.any?
    end

    # Faces shown in the header row: one avatar per actor in the aggregate,
    # capped so a very popular post doesn't overflow. Fewer actors → fewer
    # avatars (3 likers shows 3); a non-aggregated notification shows one.
    HEADER_AVATAR_CAP = 10

    def header_avatars
      (expandable? ? aggregated_actors.first(HEADER_AVATAR_CAP) : [ avatar_actor ]).compact
    end
  end
end
