# frozen_string_literal: true

class Gorse::SyncPostJob < ApplicationJob
  queue_as :default

  def perform(post)
    post.sync_to_gorse_now
  end
end
