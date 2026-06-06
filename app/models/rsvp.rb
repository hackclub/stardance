# == Schema Information
#
# Table name: rsvps
#
#  id                          :bigint           not null, primary key
#  click_confirmed_at          :datetime
#  confirmation_token          :string
#  email                       :string           not null
#  geocoded_country            :string
#  geocoded_lat                :float
#  geocoded_lon                :float
#  geocoded_subdivision        :string
#  ip_address                  :string
#  ref                         :string
#  reply_confirmed_at          :datetime
#  signup_confirmation_sent_at :datetime
#  synced_at                   :datetime
#  user_agent                  :string
#  user_ref                    :string
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#
# Indexes
#
#  index_rsvps_on_confirmation_token  (confirmation_token) UNIQUE
#
class Rsvp < ApplicationRecord
  AMBASSADOR_REFERRAL_PREFIX = "a-".freeze
  USER_REF_OPTIONS = [
    "HackClub",
    "NASA",
    "AMD",
    "GitHub",
    "Linus Tech Tips",
    "Teacher",
    "Friend"
  ].freeze

  has_paper_trail ignore: [ :ip_address, :user_agent ]
  has_secure_token :confirmation_token

  has_many :replies, class_name: "Rsvp::Reply", dependent: :destroy
  has_many :games,   class_name: "Rsvp::Game",  dependent: :destroy

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :user_ref, length: { maximum: 100 }, allow_blank: true
  before_validation :downcase_email
  after_commit :deliver_signup_confirmation, on: :create
  after_commit :enqueue_geocode_job, on: :create
  after_commit :increment_signup_counter, on: :create, if: -> { Flipper.enabled?(:new_onboarding) }

  scope :ambassador_referrals, -> {
    where(arel_table[:ref].lower.matches("#{AMBASSADOR_REFERRAL_PREFIX}%"))
  }
  scope :matching_ref, ->(ref) {
    where(arel_table[:ref].lower.eq(ref.to_s.downcase))
  }

  def ambassador_referral_payload
    {
      id: id,
      email: email,
      ref: ref,
      user_ref: user_ref,
      click_confirmed_at: click_confirmed_at,
      reply_confirmed_at: reply_confirmed_at,
      signup_confirmation_sent_at: signup_confirmation_sent_at,
      synced_at: synced_at,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def deliver_signup_confirmation
    return if signup_confirmation_sent_at?

    regenerate_confirmation_token if confirmation_token.blank?
    Rsvp::Mailer.signup_confirmation(self).deliver_later
    update_column(:signup_confirmation_sent_at, Time.current)
  end

  def confirm_click!
    return if click_confirmed_at?

    update_column(:click_confirmed_at, Time.current)
  end

  def confirm_reply!
    return if reply_confirmed_at?

    update_column(:reply_confirmed_at, Time.current)
  end

  private

  def downcase_email
    self.email = email.downcase if email.present?
  end

  def enqueue_geocode_job = RsvpGeocodeJob.perform_later(id)

  def increment_signup_counter
    Rails.cache.increment("landing/signup_count", 1, expires_in: 30.seconds)
  end
end
