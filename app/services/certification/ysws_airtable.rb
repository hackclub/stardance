# frozen_string_literal: true

module Certification
  # Single source of truth for the "YSWS Project Submission" Airtable table that
  # completed YSWS reviews are upserted into. Both the sync job and the review
  # model reach Airtable through here so the credential fallbacks live in one
  # place.
  module YswsAirtable
    DEFAULT_TABLE_NAME = "YSWS Project Submission"

    class << self
      def table
        Norairrecord.table(api_key, base_id, table_name)
      end

      # The submission record for one review, or nil when Airtable has none.
      # Reviews carry no stored Airtable record id, so filtering on the
      # review_id field is the only way to reach the record.
      def record_for(review_id)
        table.all(filter: "{review_id} = '#{review_id}'").first
      end

      def table_name
        Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
          ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
          DEFAULT_TABLE_NAME
      end

      def api_key
        Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
          Rails.application.credentials&.airtable&.api_key ||
          ENV["AIRTABLE_API_KEY"]
      end

      def base_id
        Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
          ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
      end
    end
  end
end
