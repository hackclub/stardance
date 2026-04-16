class Airtable::UserClubPullJob < ApplicationJob
  queue_as :literally_whenever
  retry_on Norairrecord::Error, wait: :polynomially_longer, attempts: 3

  def perform
    airtable_records = table.all(fields: %w[email club_name\ (from\ club) club_link])
    records_by_email = airtable_records.each_with_object({}) do |record, hash|
      email = record["email"].to_s.downcase.strip
      hash[email] = record if email.present?
    end

    User.where.not(email: [ nil, "" ]).find_each do |user|
      record = records_by_email[user.email.to_s.downcase.strip]
      next unless record

      updates = {}
      updates[:airtable_record_id] = record.id if user.airtable_record_id != record.id

      club_name = record["club_name (from club)"]
      club_name = club_name.first if club_name.is_a?(Array)
      updates[:club_name] = club_name if user.club_name != club_name

      club_link = record["club_link"]
      updates[:club_link] = club_link if user.club_link != club_link

      if updates.any?
        newly_linked = user.club_name.blank? && updates[:club_name].present?
        user.update_columns(updates)
        user.dm_user("🏫 Your Hack Club (*#{updates[:club_name]}*) has been linked to your Stardance account!") if newly_linked
      end
    end
  end

  private

  def table
    @table ||= Norairrecord.table(
      Rails.application.credentials&.airtable&.api_key || ENV["AIRTABLE_API_KEY"],
      Rails.application.credentials&.airtable&.base_id || ENV["AIRTABLE_BASE_ID"],
      "_users"
    )
  end
end
