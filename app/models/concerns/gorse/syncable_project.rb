# frozen_string_literal: true

module Gorse::SyncableProject
  extend ActiveSupport::Concern

  included do
    after_commit :sync_to_gorse_later, on: [ :create, :update ]
    after_update_commit :sync_hardware_posts_to_gorse_later,
      if: -> { saved_change_to_hardware_stage? && hardware? != hardware_stage_before_last_save.present? }
  end

  def sync_to_gorse_later
    if Gorse.enabled?
      Gorse::SyncProjectJob.perform_later(self)
    end
  end

  def sync_to_gorse_now
    Gorse::Client.new.upsert_item(Gorse::ProjectPayload.new(self).to_h)
  end

  def sync_hardware_posts_to_gorse_later
    return unless Gorse.enabled?

    posts.find_each(&:sync_to_gorse_later)
    repost_ids = Post::Repost.where(original_post_id: posts.select(:id)).select(:id)
    Post.of_reposts.where(postable_id: repost_ids).find_each(&:sync_to_gorse_later)
  end
end
