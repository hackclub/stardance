# frozen_string_literal: true

module Gorse::SyncableUser
  extend ActiveSupport::Concern

  included do
    after_commit :sync_to_gorse_later, on: [ :create, :update ]
  end

  def sync_to_gorse_later
    if Gorse.enabled?
      Gorse::SyncUserJob.perform_later(self)
    end
  end

  def sync_to_gorse_now
    Gorse::Client.new.upsert_user(Gorse::UserPayload.new(self).to_h)
  end
end
