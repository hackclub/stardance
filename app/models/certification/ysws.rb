# == Schema Information
#
# Table name: certification_ysws_reviews
#
#  id                    :bigint           not null, primary key
#  airtable_synced_at    :datetime
#  approved_minutes      :integer
#  demo_checked_at       :datetime
#  in_unified_db         :string
#  original_minutes      :integer
#  repo_checked_at       :datetime
#  returned_at           :datetime
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
    belongs_to :project, -> { with_deleted }, optional: true
    belongs_to :ship_cert, class_name: "Certification::Ship", optional: true
    belongs_to :post_ship_event, class_name: "Post::ShipEvent"
    belongs_to :spotchecked_by, class_name: "User", optional: true

    has_many :devlog_reviews, class_name: "Certification::Devlog", foreign_key: :ysws_review_id, dependent: :destroy

    validates :original_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false
    validates :approved_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    MIN_APPROVED_MINUTES = 6

    def approved_minutes_total
      devlog_reviews.sum { |dr| dr.approved_minutes.to_i }
    end

    def review_rejected?
      user.banned? || approved_minutes_total < MIN_APPROVED_MINUTES
    end

    def review_status
      return :in_unified_db if in_unified_db.present?
      return :returned if returned_at.present?
      return :pending unless reviewed_at.present?

      review_rejected? ? :rejected : :approved
    end

    def check_and_update_unified_db_status!
      api_key  = Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
                 Rails.application.credentials&.airtable&.api_key ||
                 ENV["AIRTABLE_API_KEY"]
      base_id  = Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
                 ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
      tbl_name = Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
                 ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
                 "YSWS Project Submission"

      table = Norairrecord.table(api_key, base_id, tbl_name)
      record = table.all(filter: "{review_id} = '#{id}'").first
      unified_record_id = record&.[]("Automation - YSWS Record ID").presence

      update_column(:in_unified_db, unified_record_id) if unified_record_id.present? && in_unified_db != unified_record_id
    rescue Faraday::Error => e
      Rails.logger.warn "[Certification::Ysws] Could not check unified DB status for ##{id}: #{e.message}"
    end
  end
end
