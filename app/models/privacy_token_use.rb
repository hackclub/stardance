# == Schema Information
#
# Table name: privacy_token_uses
#
#  jti     :string           not null, primary key
#  used_at :datetime         not null
#
# Indexes
#
#  index_privacy_token_uses_on_used_at  (used_at)
#
# One row per privacy hub token we have accepted, so a token works only once. Kept in postgres
# rather than Rails.cache, because a cache that can't be written looks the same as a key that
# already exists, which would make every token look replayed.
class PrivacyTokenUse < ApplicationRecord
  self.primary_key = :jti

  RETENTION = 1.day

  def self.record_first_use!(jti)
    where(used_at: ...RETENTION.ago).delete_all
    insert({ jti:, used_at: Time.current }, returning: :jti).any?
  end
end
