module User::UsernameBloomSync
  extend ActiveSupport::Concern

  included do
    after_commit :sync_display_name_to_bloom_filter, on: [ :create, :update ], if: :display_name_previously_changed?
  end

  private

  def sync_display_name_to_bloom_filter
    User::UsernameBloomFilter.add(display_name) if display_name.present?
  end

  def display_name_previously_changed?
    previous_changes.key?("display_name")
  end
end
