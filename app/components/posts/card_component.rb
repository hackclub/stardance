# frozen_string_literal: true

module Posts
  class CardComponent < ViewComponent::Base
    delegate :inline_svg_tag, to: :helpers

    attr_reader :post, :current_user, :theme, :compact, :show_likes, :show_comments, :show_actions

    def initialize(post:, current_user: nil, theme: :feed, compact: false, show_likes: true, show_comments: true, show_actions: true)
      @post = post
      @current_user = current_user
      @theme = theme
      @compact = compact
      @show_likes = show_likes
      @show_comments = show_comments
      @show_actions = show_actions
    end

    def render?
      post.present? && post.postable.present?
    end

    def devlog?
      post.postable_type == "Post::Devlog"
    end

    def card_classes
      class_names(
        "feed-post-card",
        "feed-post-card--compact": compact,
        "feed-post-card--#{theme}": theme.present?
      )
    end

    def author
      post.user
    end

    def project
      post.project
    end

    def postable
      post.postable
    end

    def author_name
      author&.display_name.presence || "stardancer"
    end

    def body
      postable.respond_to?(:body) ? postable.body : nil
    end

    def attachments
      if postable.respond_to?(:attachments)
        postable.attachments
      else
        []
      end
    end

    def attachment_count
      attachments.respond_to?(:count) ? attachments.count : 0
    end

    def comments_count_id
      "comments_count_#{postable.class.name.underscore.tr('/', '_')}_#{postable.id}"
    end

    def likeable
      postable if devlog?
    end

    # When the current user is the post's author and they haven't yet verified
    # their identity, surface a small badge in the card header to remind them
    # that this content is hidden from everyone except admins.
    def show_idv_badge?
      current_user.present? &&
        author.present? &&
        current_user.id == author.id &&
        !current_user.identity_verified?
    end
  end
end
