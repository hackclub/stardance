# frozen_string_literal: true

namespace :gorse do
  desc "Backfill Gorse users, posts, projects, and feedback"
  task backfill: :environment do
    unless Gorse.enabled?
      puts "Gorse is disabled. Enable credentials/env and Flipper flags before backfilling."
      next
    end

    puts "Syncing users..."
    User.find_each(&:sync_to_gorse_now)

    puts "Syncing projects..."
    Project.find_each(&:sync_to_gorse_now)

    puts "Syncing posts..."
    Post.includes(:postable).find_each do |post|
      post.sync_to_gorse_now if post.postable.present?
    end

    puts "Syncing feedback..."
    Like.includes(:user, likeable: :post).find_each do |like|
      if like.likeable_type == "Post::Devlog" && like.likeable&.post.present?
        like.send_gorse_feedback_later(user: like.user, item: like.likeable.post, feedback_type: :like, timestamp: like.created_at)
      end
    end

    Comment.includes(:user, commentable: :post).find_each do |comment|
      if comment.commentable_type == "Post::Devlog" && comment.commentable&.post.present?
        comment.send_gorse_feedback_later(user: comment.user, item: comment.commentable.post, feedback_type: :comment, timestamp: comment.created_at)
      end
    end

    Post::Repost.includes(:user, :original_post).find_each do |repost|
      repost.send_gorse_feedback_later(user: repost.user, item: repost.original_post, feedback_type: :repost, timestamp: repost.created_at)
    end

    ProjectFollow.includes(:user, :project).find_each do |follow|
      follow.send_gorse_feedback_later(user: follow.user, item: follow.project, feedback_type: :follow_project, timestamp: follow.created_at)
    end

    Vote.includes(:user, ship_event: :post).find_each do |vote|
      if vote.ship_event&.post.present?
        vote.send_gorse_feedback_later(user: vote.user, item: vote.ship_event.post, feedback_type: :vote, value: vote.score_average, timestamp: vote.created_at)
      end
    end

    Vote::Assignment.skipped.includes(:user, ship_event: :post).find_each do |assignment|
      if assignment.ship_event&.post.present?
        assignment.send_gorse_feedback_later(user: assignment.user, item: assignment.ship_event.post, feedback_type: :skip, timestamp: assignment.updated_at)
      end
    end

    puts "Backfill enqueued."
  end
end
