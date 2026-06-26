# == Schema Information
#
# Table name: expeditions
#
#  id                    :bigint           not null, primary key
#  ambassador_name       :string
#  apple_maps_url        :string
#  city                  :string
#  concluded             :boolean          default(FALSE), not null
#  country               :string
#  date                  :date
#  google_maps_url       :string
#  latitude              :float
#  longitude             :float
#  participant_slack_ids :string           default([]), not null, is an Array
#  season                :string
#  slug                  :string
#  state                 :string
#  title                 :string           not null
#  venue_address         :string
#  venue_name            :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  airtable_id           :string           not null
#  ambassador_slack_id   :string
#  channel_id            :string
#
# Indexes
#
#  index_expeditions_on_airtable_id                (airtable_id) UNIQUE
#  index_expeditions_on_concluded_and_date_and_id  (concluded,date,id)
#  index_expeditions_on_slug                       (slug) UNIQUE
#
class Expedition < ApplicationRecord
  validates :airtable_id, :title, presence: true
  validates :airtable_id, uniqueness: true
  validates :slug, uniqueness: true, allow_blank: true

  normalizes :slug, with: ->(slug) { slug.presence }

  scope :chronological, -> { order(arel_table[:date].asc.nulls_last, :id) }
  scope :upcoming, -> { where(concluded: false).chronological }
  scope :concluded, -> { where(concluded: true).chronological }

  def self.browseable = upcoming

  def self.find_by_param!(param) = find_by(slug: param) || find_by!(airtable_id: param)

  def self.matching(query)
    term = query.to_s.squish
    return none if term.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    columns = %i[title city state country venue_name]
    where(columns.map { |column| arel_table[column].matches(pattern, nil, false) }.reduce(&:or))
  end

  def self.attributes_from_api(data)
    venue = data.fetch("venue", {}) || {}

    {
      airtable_id: data["id"],
      title: data["prettyName"].presence || data["name"].presence,
      slug: data["slug"],
      season: data["season"],
      date: date_from(data["date"]),
      concluded: data["concluded"] == true,
      venue_name: venue["name"],
      venue_address: venue["address"],
      city: venue["city"],
      state: venue["state"],
      country: venue["country"],
      latitude: float_from(data["latitude"]),
      longitude: float_from(data["longitude"]),
      channel_id: data["channelId"],
      ambassador_slack_id: data["ambassadorSlackId"],
      ambassador_name: data["ambassadorName"],
      google_maps_url: data["googleMapsUrl"],
      apple_maps_url: data["appleMapsUrl"],
      participant_slack_ids: Array(data["participantSlackIds"]).map(&:to_s)
    }
  end

  def self.date_from(value)
    Date.iso8601(value) if value.present?
  end

  def self.float_from(value)
    return if value.blank?

    Float(value).tap { |number| raise ArgumentError, "coordinate must be finite" unless number.finite? }
  end
  private_class_method :date_from, :float_from

  def to_param = slug.presence || airtable_id

  def attending?(slack_id) = slack_id.present? && participant_slack_ids.include?(slack_id)

  def location
    region = [ city, state.presence || country ].compact_blank.join(", ")
    region.presence || "Location TBA"
  end

  def distance_km_from(origin_lat, origin_lon)
    return nil unless latitude && longitude

    d_lat = deg2rad(latitude - origin_lat)
    d_lon = deg2rad(longitude - origin_lon)
    a = Math.sin(d_lat / 2)**2 +
        Math.cos(deg2rad(origin_lat)) * Math.cos(deg2rad(latitude)) * Math.sin(d_lon / 2)**2
    2 * 6371.0 * Math.asin(Math.sqrt(a))
  end

  def slack_channel_url
    "https://hackclub.slack.com/archives/#{channel_id}" if channel_id.present?
  end

  def ambassador_slack_url
    "https://hackclub.slack.com/team/#{ambassador_slack_id}" if ambassador_slack_id.present?
  end

  def deg2rad(degrees) = degrees * Math::PI / 180
  private :deg2rad
end
