# frozen_string_literal: true

module Posts
  class CardComponent < ViewComponent::Base
    delegate :inline_svg_tag, to: :helpers

    attr_reader :post, :current_user, :theme, :compact, :show_likes, :show_comments, :show_reposts, :show_actions, :liked_devlog_ids, :reposted_post_ids

    def initialize(post:, current_user: nil, theme: :feed, compact: false, show_likes: true, show_comments: true, show_reposts: true, show_actions: true, liked_devlog_ids: nil, reposted_post_ids: nil)
      @post = post
      @current_user = current_user
      @theme = theme
      @compact = compact
      @show_likes = show_likes
      @show_comments = show_comments
      @show_reposts = show_reposts
      @show_actions = show_actions
      @liked_devlog_ids = liked_devlog_ids
      @reposted_post_ids = reposted_post_ids
    end

    def render?
      post.present? && post.postable.present?
    end

    def devlog?
      display_post&.postable_type == "Post::Devlog"
    end

    def repost?
      post.postable_type == "Post::Repost"
    end

    def plain_repost?
      repost? && postable.body.blank? && original_post.present?
    end

    def quote_repost?
      repost? && !plain_repost?
    end

    def card_classes
      class_names(
        "feed-post-card",
        "feed-post-card--linked": card_link_url.present?,
        "feed-post-card--compact": compact,
        "feed-post-card--quote-repost": quote_repost?,
        "feed-post-card--#{theme}": theme.present?
      )
    end

    def card_link_url
      if interaction_post&.postable_type == "Post::Devlog" && interaction_post.project.present?
        helpers.project_devlog_path(interaction_post.project, interaction_postable)
      end
    end

    def author
      display_post&.user
    end

    def project
      display_post&.project
    end

    def postable
      post.postable
    end

    def display_post
      plain_repost? ? original_post : post
    end

    def display_postable
      display_post&.postable
    end

    def author_name
      author&.display_name.presence || "stardancer"
    end

    def body
      display_postable.respond_to?(:body) ? display_postable.body : nil
    end

    def original_post
      postable.original_post if repost? && postable.respond_to?(:original_post)
    end

    def attachments
      @attachments ||= if display_postable.respond_to?(:attachments)
        display_postable.attachments
      else
        []
      end
    end

    def attachment_count
      attachments.respond_to?(:size) ? attachments.size : 0
    end

    def show_footer?
      show_comments || show_reposts || show_likes || show_actions
    end

    def comment_url
      card_link_url || "#"
    end

    def comments_count_id
      if interaction_postable.present?
        "comments_count_#{interaction_postable.class.name.underscore.tr('/', '_')}_#{interaction_postable.id}"
      end
    end

    def likeable
      interaction_postable if interaction_post&.postable_type == "Post::Devlog"
    end

    def repost_target
      if display_post&.postable_type == "Post::Devlog"
        display_post
      elsif repost?
        original_post
      end
    end

    def interaction_post
      repost_target
    end

    def interaction_postable
      interaction_post&.postable
    end

    def repostable?
      repost_target&.postable_type == "Post::Devlog"
    end

    def repost_count
      repost_target&.reposts_count.to_i
    end

    def reposted_by_current_user?
      return false unless current_user.present? && repostable?
      return reposted_post_ids.include?(repost_target.id) unless reposted_post_ids.nil?

      Post::Repost.exists?(original_post: repost_target, user: current_user)
    end

    def quote_dialog_id
      helpers.dom_id(repost_target, :quote_repost)
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

    def can_edit?
      action_allowed?(:edit?)
    end

    def can_delete?
      action_allowed?(:destroy?)
    end

    def post_url
      if card_link_url.present?
        card_link_url
      elsif project.present?
        helpers.project_path(project, anchor: helpers.dom_id(post))
      else
        "#"
      end
    end

    def edit_url
      if devlog? && project.present?
        helpers.edit_project_devlog_path(project, postable)
      end
    end

    def delete_url
      if devlog? && project.present?
        helpers.project_devlog_path(project, postable)
      end
    end

    def action_allowed?(action)
      if current_user.present? && devlog?
        helpers.policy(postable).public_send(action)
      else
        false
      end
    end
  end
end
