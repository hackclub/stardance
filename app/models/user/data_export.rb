# == Schema Information
#
# Table name: user_data_exports
#
#  id            :bigint           not null, primary key
#  error_message :text
#  status        :string           default("pending"), not null
#  zip_filename  :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_user_data_exports_on_user_id             (user_id)
#  index_user_data_exports_on_user_id_active      (user_id) UNIQUE WHERE (((status)::text = 'pending'::text) OR ((status)::text = 'processing'::text))
#  index_user_data_exports_on_user_id_and_status  (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class User::DataExport < ApplicationRecord
  ACTIVE_STATUSES = %w[pending processing].freeze
  RETENTION_PERIOD = 7.days
  STALE_AFTER = 6.hours

  belongs_to :user
  has_one_attached :zip_file, dependent: :purge_later

  validates :status, inclusion: { in: %w[pending processing completed failed] }

  scope :completed, -> { where(status: "completed") }
  scope :expired, -> { where("created_at < ?", RETENTION_PERIOD.ago) }
  scope :retained, -> { where(created_at: RETENTION_PERIOD.ago..) }
  scope :pending_or_processing, -> { where(status: ACTIVE_STATUSES) }
  scope :stale_active, -> { pending_or_processing.where("updated_at < ?", STALE_AFTER.ago) }

  def self.purge_expired!
    expired.find_each(&:destroy!)
  end

  def download_available?
    completed? && !expired? && zip_file.attached?
  end

  def expires_at
    created_at + RETENTION_PERIOD
  end

  def expired?
    expires_at < Time.current
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def processing?
    status == "processing"
  end

  def pending?
    status == "pending"
  end
end
