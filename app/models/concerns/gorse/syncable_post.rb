# frozen_string_literal: true

module Gorse::SyncablePost
  extend ActiveSupport::Concern

  included do
    after_commit :sync_to_gorse_later, on: [ :create, :update ]
  end

  def sync_to_gorse_later
    if Gorse.enabled? && Flipper.enabled?(:gorse_personalized_feed)
      Gorse::SyncPostJob.perform_later(self)
    end
  end

  def sync_to_gorse_now
    Gorse::Client.new.upsert_item(Gorse::PostPayload.new(self).to_h)
  end
end
