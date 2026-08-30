# frozen_string_literal: true

class Gorse::SyncUserJob < ApplicationJob
  queue_as :literally_whenever

  def perform(user)
    user.sync_to_gorse_now
  end
end
