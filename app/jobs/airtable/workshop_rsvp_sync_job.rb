class Airtable::WorkshopRsvpSyncJob < ApplicationJob
  TABLE_ID = "tbleo5vkRpWz0dYH7"
  EMAIL_FIELD = "Email"
  SIGNUP_NAMES_FIELD = "Loops - stardanceWorkshopSignUpNames"

  queue_as :literally_whenever

  limits_concurrency to: 1, key: ->(user_id, _workshop_id) { user_id }, duration: 5.minutes
  retry_on Norairrecord::Error, wait: :polynomially_longer, attempts: 3

  def perform(user_id, workshop_id)
    user = User.find_by(id: user_id)
    workshop = Workshop.find_by(id: workshop_id)
    return unless user&.email.present? && workshop

    email = user.email.downcase.strip
    record = find_record(email)
    signup_names = merge_signup_names(record&.[](SIGNUP_NAMES_FIELD), signup_name(workshop))

    if record
      return if record[SIGNUP_NAMES_FIELD].to_s == signup_names

      record.patch(SIGNUP_NAMES_FIELD => signup_names)
    else
      table.create(
        EMAIL_FIELD => email,
        SIGNUP_NAMES_FIELD => signup_names
      )
    end
  end

  private

    def find_record(email)
      table.all(filter: "LOWER({#{EMAIL_FIELD}}) = '#{escape_formula_string(email)}'").first
    end

    def signup_name(workshop)
      date = workshop.starts_at.in_time_zone(Workshop::TIME_ZONE).to_date.iso8601
      "#{workshop.title.strip} #{date}"
    end

    def merge_signup_names(current_value, new_signup_name)
      (current_value.to_s.split(",") + [ new_signup_name ])
        .map(&:strip)
        .reject(&:blank?)
        .uniq { |name| name.downcase }
        .join(", ")
    end

    def escape_formula_string(value)
      value.gsub(/['\\]/) { |character| "\\#{character}" }
    end

    def table
      @table ||= Norairrecord.table(
        Rails.application.credentials&.airtable&.api_key || ENV["AIRTABLE_API_KEY"],
        Rails.application.credentials&.airtable&.base_id || ENV["AIRTABLE_BASE_ID"],
        TABLE_ID
      )
    end
end
