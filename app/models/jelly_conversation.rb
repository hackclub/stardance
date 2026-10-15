# == Schema Information
#
# Table name: jelly_conversations
#
#  id                     :bigint           not null, primary key
#  assignee_count         :integer          default(0), not null
#  first_response_seconds :integer
#  last_inbound_at        :datetime
#  last_outbound_at       :datetime
#  messages_synced_at     :datetime
#  opened_at              :datetime
#  remote_updated_at      :datetime
#  resolved_at            :datetime
#  status                 :string           not null
#  synced_at              :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  jelly_id               :string           not null
#
# Indexes
#
#  index_jelly_conversations_on_jelly_id           (jelly_id) UNIQUE
#  index_jelly_conversations_on_remote_updated_at  (remote_updated_at)
#  index_jelly_conversations_on_status             (status)
#
class JellyConversation < ApplicationRecord
  OPEN_STATUS = "open".freeze
  # Beyond this the local mirror is old enough that the panel says so rather
  # than presenting the numbers as current.
  STALE_AFTER = 45.minutes

  scope :open_now, -> { where(status: OPEN_STATUS) }
  # Awaiting a reply from us: the last thing that happened was inbound.
  scope :awaiting_reply, -> {
    open_now.where.not(last_inbound_at: nil)
            .where("last_outbound_at IS NULL OR last_outbound_at < last_inbound_at")
  }
  # Deliberately not scoped to open conversations. First response time has to
  # be measured across resolved ones too: the still-open set is exactly the
  # slow and unanswered tail, so a median taken from it alone reads far worse
  # than reality. Archived conversations stop matching once their messages are
  # synced, so this converges instead of refetching forever.
  scope :needing_message_sync, -> {
    where("messages_synced_at IS NULL OR messages_synced_at < remote_updated_at")
  }

  def self.watermark = maximum(:remote_updated_at)

  def self.last_synced_at = maximum(:synced_at)

  def self.stale? = last_synced_at.nil? || last_synced_at < STALE_AFTER.ago

  # How long the requester has been waiting on us right now, in seconds.
  def hang_seconds(now: Time.current)
    return unless last_inbound_at
    return if last_outbound_at && last_outbound_at >= last_inbound_at

    now - last_inbound_at
  end
end
