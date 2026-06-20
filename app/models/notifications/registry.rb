module Notifications
  module Registry
    # Explicit list of registered notification subclasses. New types must be
    # added here so they show up in the preferences UI and the dev lab.
    # An explicit list is used instead of `Notification.descendants` because
    # STI descendants are not reliably loaded in development.
    TYPES = %w[
      Notifications::NewFollower
      Notifications::ProjectFollowed
      Notifications::FollowedDevlogCreated
      Notifications::ProjectCommentReceived
      Notifications::MentionReceived
      Notifications::DevlogLiked
      Notifications::DevlogReposted
      Notifications::DevlogQuoteReposted
      Notifications::Missions::SubmissionApproved
      Notifications::Missions::SubmissionRejected
      Notifications::Missions::SubmissionPendingForReviewer
      Notifications::Projects::SuperStar
      Notifications::AchievementEarned
      Notifications::StardustBalanceChanged
      Notifications::Payouts::ShipEventIssued
      Notifications::Payouts::VoteDeficitBlocked
      Notifications::ShopOrders::StatusChanged
    ].freeze

    module_function

    def all
      TYPES.map(&:constantize)
    end

    def by_category(category)
      all.find { |klass| klass.category_key.to_s == category.to_s }
    end

    def grouped_by_priority
      all.group_by(&:default_priority)
    end
  end
end
