# == Schema Information
#
# Table name: certification_ysws_reviews
#
#  id                    :bigint           not null, primary key
#  airtable_synced_at    :datetime
#  approved_minutes      :integer
#  demo_checked_at       :datetime
#  original_minutes      :integer
#  repo_checked_at       :datetime
#  reviewed_at           :datetime
#  spotchecked_at        :datetime
#  summary_justification :text
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  post_ship_event_id    :bigint           not null
#  project_id            :bigint           not null
#  reviewer_id           :bigint
#  ship_cert_id          :bigint
#  spotchecked_by_id     :bigint
#  user_id               :bigint           not null
#
# Indexes
#
#  index_certification_ysws_reviews_on_post_ship_event_id  (post_ship_event_id)
#  index_certification_ysws_reviews_on_project_id          (project_id)
#  index_certification_ysws_reviews_on_reviewer_id         (reviewer_id)
#  index_certification_ysws_reviews_on_ship_cert_id        (ship_cert_id)
#  index_certification_ysws_reviews_on_spotchecked_by_id   (spotchecked_by_id)
#  index_certification_ysws_reviews_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (post_ship_event_id => post_ship_events.id)
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (ship_cert_id => certification_ship_reviews.id)
#  fk_rails_...  (spotchecked_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
module Certification
  class Ysws < ApplicationRecord
    self.table_name = "certification_ysws_reviews"

    belongs_to :reviewer, class_name: "User", optional: true
    belongs_to :user
    belongs_to :project
    belongs_to :ship_cert, class_name: "Certification::Ship", optional: true
    belongs_to :post_ship_event, class_name: "Post::ShipEvent"
    belongs_to :spotchecked_by, class_name: "User", optional: true

    has_many :devlog_reviews, class_name: "Certification::Devlog", foreign_key: :ysws_review_id, dependent: :destroy

    validates :original_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false
    validates :approved_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # Check if this review has been moved to the unified DB and update the flag
    def check_and_update_unified_db_status!
      # Skip check if already marked as in unified DB
      return true if in_unified_db?

      begin
        # Fetch record from Airtable
        table = airtable_table
        existing_record = table.all(filter: "{review_id} = '#{id}'").first

        # If record exists and "Automation - YSWS Record ID" is populated, mark as in unified DB
        if existing_record && existing_record["Automation - YSWS Record ID"].present?
          update_column(:in_unified_db, true)
          true
        else
          false
        end
      rescue StandardError => e
        # Log error but don't break the calling code
        Rails.logger.warn "[Certification::Ysws] Could not check unified DB status for review ##{id}: #{e.message}"
        Sentry.capture_exception(e, extra: { ysws_review_id: id })
        false
      end
    end

    private

    def airtable_table
      api_key = Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
                Rails.application.credentials&.airtable&.api_key ||
                ENV["AIRTABLE_API_KEY"]
      base_id = Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
                ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
      table_name = Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
                   ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
                   "YSWS Project Submission"

      Norairrecord.table(api_key, base_id, table_name)
    end
  end
end
