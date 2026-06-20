# frozen_string_literal: true

class Gorse::PostPayload
  def initialize(post)
    @post = post
  end

  def self.feed_scope(viewer)
    Post.with(
      feed_entries: [
        Post.of_devlogs(join: true)
            .where(post_devlogs: { deleted_at: nil })
            .where(project_id: Project.not_deleted)
            .select("posts.*"),
        Post.of_ship_events(join: true)
            .where.not(post_ship_events: { certification_status: "rejected" })
            .where(project_id: Project.not_deleted)
            .select("posts.*"),
        # Collapse a viral post's reposts: keep only the most recent repost per
        # original so a single popular post can't flood the feed with one card
        # per reposter.
        Post.of_reposts(join: true)
            .where(post_reposts: { deleted_at: nil })
            .select("DISTINCT ON (post_reposts.original_post_id) posts.*")
            .order("post_reposts.original_post_id, posts.created_at DESC")
      ]
    )
    .from("feed_entries AS posts")
    .visible_to(viewer)
  end

  def to_h
    {
      ItemId: Gorse::Ids.post(post),
      Categories: categories,
      Labels: labels,
      Timestamp: post.created_at.iso8601,
      IsHidden: hidden?,
      Comment: comment
    }
  end

  def hidden?
    post.postable.blank? ||
      hidden_devlog? ||
      hidden_ship_event? ||
      post.project&.deleted_at.present? ||
      post.user&.identity_verified? == false ||
      post.user&.banned?
  end

  private
    attr_reader :post

    def categories
      [ "feed", post_type, post.project&.project_type ].compact_blank.uniq
    end

    def labels
      Gorse::Labels.cast(
        type: post_type,
        project_id: post.project_id,
        author_id: post.user_id,
        project_type: post.project&.project_type,
        has_media: has_media?,
        certification_status: ship_certification_status
      )
    end

    def post_type
      post.postable_type.to_s.demodulize.underscore
    end

    def comment
      if post.postable.respond_to?(:body)
        post.postable.body.to_s.truncate(240)
      else
        post.project&.title.to_s
      end
    end

    def hidden_devlog?
      post.postable_type == "Post::Devlog" && post.postable.deleted?
    end

    def hidden_ship_event?
      post.postable_type == "Post::ShipEvent" && post.postable.certification_status == "rejected"
    end

    def has_media?
      post.postable.respond_to?(:attachments) && post.postable.attachments.attached?
    end

    def ship_certification_status
      if post.postable_type == "Post::ShipEvent"
        post.postable.certification_status
      end
    end
end
