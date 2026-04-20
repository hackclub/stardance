class Airtable::RsvpSyncJob < Airtable::BaseSyncJob
  def table_name = "_rsvps"

  def records = Rsvp.includes(:replies)

  def primary_key_field = "email"

  def null_sync_limit = 100

  def field_mapping(rsvp)
    {
      "email" => rsvp.email,
      "ip" => rsvp&.ip_address,
      "user_agent" => rsvp&.user_agent,
      "ref" => rsvp&.ref,
      "created_at" => rsvp.created_at,
      "updated_at" => rsvp.updated_at,
      "signup_confirmation_sent_at" => rsvp.signup_confirmation_sent_at,
      "click_confirmed_at" => rsvp.click_confirmed_at,
      "reply_confirmed_at" => rsvp.reply_confirmed_at,
      "replies_count" => rsvp.replies.size,
      "synced_at" => Time.now,
      "star_id" => rsvp.id.to_s,
      "geocoded_lat" => rsvp.geocoded_lat,
      "geocoded_lon" => rsvp.geocoded_lon,
      "geocoded_country" => rsvp.geocoded_country,
      "geocoded_subdivision" => rsvp.geocoded_subdivision
    }
  end
end
