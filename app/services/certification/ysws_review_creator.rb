module Certification
  class YswsReviewCreator
    attr_reader :ship_event, :user, :project, :ship_cert_id

    def initialize(ship_event:, user:, project:, ship_cert_id: nil)
      @ship_event = ship_event
      @user = user
      @project = project
      @ship_cert_id = ship_cert_id
    end

    def call
      ActiveRecord::Base.transaction do
        devlog_posts = devlogs_since_last_ship.to_a
        # "Original" reflects ALL logged time across the ship window (every
        # phase), independent of Post::ShipEvent#hours, which is the build-only
        # deflated payout basis. Reviewers deflate from this raw baseline.
        original_minutes = devlog_posts.sum { |post| (post.postable&.duration_seconds || 0) / 60 }

        ysws_review = create_ysws_review(original_minutes)
        create_devlog_reviews(ysws_review, devlog_posts)
        ysws_review
      end
    end

    private

    def create_ysws_review(original_minutes)
      Certification::Ysws.create!(
        user: user,
        project: project,
        post_ship_event: ship_event,
        ship_cert_id: ship_cert_id,
        original_minutes: original_minutes,
        approved_minutes: nil, # Will be set by reviewer
        reviewed_at: nil, # Will be set when reviewed
        reviewer_id: nil # Will be assigned by admin
      )
    end

    def create_devlog_reviews(ysws_review, devlog_posts)
      devlog_posts.each do |post|
        devlog = post.postable
        devlog_minutes = (devlog.duration_seconds || 0) / 60

        Certification::Devlog.create!(
          post_devlog: devlog,
          ysws_review: ysws_review,
          original_minutes: devlog_minutes,
          approved_minutes: nil, # Will be set by reviewer
          justification: nil, # Will be set by reviewer
          status: :pending
        )
      end
    end

    def devlogs_since_last_ship
      start_time, end_time = time_range_since_previous_ship

      project.posts.of_devlogs(join: true)
             .where("posts.created_at >= ? AND posts.created_at <= ?", start_time, end_time)
             .where(post_devlogs: { deleted_at: nil })
             .order("posts.created_at ASC")
    end

    def time_range_since_previous_ship
      ship_event_post = ship_event.post
      previous_ship_event_post = project.posts.of_ship_events
                                        .where("posts.created_at < ?", ship_event_post.created_at)
                                        .order("posts.created_at DESC")
                                        .first

      start_time = previous_ship_event_post ? previous_ship_event_post.created_at : project.created_at
      end_time = ship_event_post.created_at

      [ start_time, end_time ]
    end
  end
end
