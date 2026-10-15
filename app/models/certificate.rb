# == Schema Information
#
# Table name: certificates
#
#  id             :bigint           not null, primary key
#  code           :string           not null
#  hours_at_issue :float            not null
#  name           :string           not null
#  status         :string           default("pending"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_certificates_on_code     (code) UNIQUE
#  index_certificates_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Certificate < ApplicationRecord
  REQUIRED_APPROVED_HOURS = 30
  CODE_LETTERS = (("A".."Z").to_a - %w[I O]).freeze
  CODE_DIGITS = ("2".."9").to_a.freeze
  CODE_FORMAT = /\A(?:[A-Z]\d){3}\z/
  NAME_MAX_LENGTH = 40

  belongs_to :user

  has_paper_trail

  enum :status, %w[pending approved rejected].index_by(&:itself), default: "pending"

  before_validation :generate_code, on: :create
  after_save :award_certificate_achievement, if: -> { approved? && saved_change_to_status? }

  validates :code, presence: true, uniqueness: true, format: { with: CODE_FORMAT }
  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :hours_at_issue, presence: true
  validates :user_id, uniqueness: true

  def self.normalize_code(raw)
    raw.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  # The one entry point for user requests (initial and post-rejection).
  # Names matching the holder's verified HCA identity issue instantly (under
  # the verified spelling, since the match ignores case and whitespace),
  # while anything custom (re-)enters the admin review queue, even when the
  # name is unchanged. A code collision with a concurrent insert gets a fresh
  # code and retries, so RecordNotUnique only ever escapes for a duplicate user.
  def request_with(requested_name)
    self.name = requested_name.to_s.squish
    if matches_verified_name?
      self.name = user.full_name.to_s.squish
      self.status = "approved"
    else
      self.status = "pending"
    end

    attempts = 0
    begin
      save
    rescue ActiveRecord::RecordNotUnique => e
      raise unless e.message.include?("index_certificates_on_code") && (attempts += 1) <= 3
      self.code = nil
      retry
    end
  end

  def matches_verified_name?
    name.to_s.strip.casecmp?(user.full_name.to_s.strip)
  end

  # Distinct live projects behind the holder's approved ships, printed on
  # the certificate art.
  def approved_projects_count
    return 0 unless user

    Post.approved_ship_events_by(user).distinct.count(:project_id)
  end

  private

  def award_certificate_achievement
    user.award_achievement!(:certificate_earned)
  end

  def generate_code
    return if code.present?

    self.code = loop do
      candidate = Array.new(3) { CODE_LETTERS.sample + CODE_DIGITS.sample }.join
      break candidate unless self.class.exists?(code: candidate)
    end
  end
end
