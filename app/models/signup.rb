# Read-only window onto the materialized_all_signups view: one row per
# normalized signup email across users and RSVPs, banned users excluded.
# Refreshed every 2 minutes by RefreshMaterializedAllSignupsJob; the view is
# created in-migration and intentionally lives outside schema.rb.
# == Schema Information
#
# Table name: materialized_all_signups
#
#  actual_referral_source       :text
#  actual_referral_source_from  :text
#  amd_referral_group           :text
#  assumed_referral_source      :text
#  assumed_referral_source_rate :decimal(, )
#  country                      :text
#  country_code                 :string
#  email                        :text             primary key
#  first_seen_at_utc            :datetime
#  first_seen_day_et            :date
#  geocode_methodology          :text
#  gpu_raffle_referral_group    :text
#  ip_address                   :string
#  is_ambassador_signup         :boolean
#  is_gpu_raffle_signup         :boolean
#  is_us                        :boolean
#  known_referral_source        :text
#  latitude                     :float
#  longitude                    :float
#  missing_referral_source      :boolean
#  nasa_referral_group          :text
#  primary_referral_methodology :text
#  primary_referral_source      :text
#  raw_refs                     :text             is an Array
#  raw_user_refs                :text             is an Array
#  region                       :text
#  region_code                  :string
#  seen_in_rsvps                :boolean
#  seen_in_users                :boolean
#  source_group                 :text
#
# Indexes
#
#  index_materialized_all_signups_on_email  (email) UNIQUE
#
class Signup < ApplicationRecord
  self.table_name = "materialized_all_signups"
  self.primary_key = "email"

  # First match wins, so non-viral categories must come before viral ones they
  # could shadow ("school teacher" is a teacher referral, not a school one).
  REF_CATEGORIES = {
    friend: /\bfriends?\b/,
    family: /\b(mom|dad|parents?|family|brother|sister|sibling|cousin|aunt|uncle|grandma|grandpa|grandmother|grandfather|grandparent)\b/,
    teacher: /\b(teacher|professor|principal|counselor|advisor)\b/,
    school: /\b(school|library|classroom)\b/,
    community_chat: /\b(discord|slack|telegram|whatsapp)\b/,
    social_media: /\b(youtube|tiktok|instagram|insta|reddit|twitter|facebook|linkedin|linus tech tips|social media|youtuber|streamer|creator)\b/
  }.freeze

  # Word-of-mouth channels: signups that came from a person telling a person.
  VIRAL_CATEGORIES = %i[ambassador gpu_raffle friend family school community_chat social_media].freeze

  scope :first_seen_since, ->(time) { where(first_seen_at_utc: time..) }

  def readonly?
    true
  end

  # Share (0..1) of the window's signups that arrived through viral channels,
  # or nil when the window has no signups. Defaults to the current calendar
  # week (Monday start), matching date_trunc('week', ...) in Metabase.
  def self.virality_factor(since: Time.current.beginning_of_week)
    signups = first_seen_since(since).pluck(:is_ambassador_signup, :is_gpu_raffle_signup, :known_referral_source)
    return nil if signups.empty?

    viral = signups.count { |ambassador, raffle, ref| VIRAL_CATEGORIES.include?(referral_category(ambassador, raffle, ref)) }
    viral.fdiv(signups.size)
  end

  def self.referral_category(ambassador, raffle, ref)
    return :ambassador if ambassador
    return :gpu_raffle if raffle
    return :unknown if ref.blank?

    text = ref.downcase
    REF_CATEGORIES.each_key.find { |category| text.match?(REF_CATEGORIES[category]) } || :other
  end
end
