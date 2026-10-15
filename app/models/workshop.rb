# == Schema Information
#
# Table name: workshops
#
#  id                :bigint           not null, primary key
#  description       :text
#  ends_at           :datetime         not null
#  rsvps_notified_at :datetime
#  starts_at         :datetime         not null
#  title             :string           not null
#  zoom_link         :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_workshops_on_starts_at  (starts_at)
#
class Workshop < ApplicationRecord
  has_paper_trail

  # How long before the start time the Zoom link opens and RSVPs get notified.
  JOIN_WINDOW = 15.minutes

  # Admin forms/pages work in Eastern; viewers see their own local time.
  TIME_ZONE = "America/New_York"

  has_many :rsvps, class_name: "Workshop::Rsvp", dependent: :destroy
  has_many :rsvped_users, through: :rsvps, source: :user
  has_many :attendances, class_name: "Workshop::Attendance", dependent: :destroy
  has_many :attendees, through: :attendances, source: :user

  validates :title, presence: true
  # Blank until the host drops the link in shortly before start.
  validates :zoom_link, format: { with: %r{\Ahttps://\S+\z}, message: "must be an https:// URL" }, allow_blank: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validate :ends_after_start

  scope :upcoming, -> { where(ends_at: Time.current..).order(:starts_at) }
  scope :past, -> { where(ends_at: ...Time.current).order(starts_at: :desc) }

  after_commit :schedule_rsvp_notifications, if: -> { saved_change_to_starts_at? }

  def joinable?(at = Time.current)
    at.between?(starts_at - JOIN_WINDOW, ends_at)
  end

  def ended?(at = Time.current)
    at > ends_at
  end

  # Single source of truth for the page states; the JS countdown mirrors it.
  def state(at = Time.current)
    return :ended if ended?(at)
    return :live if at >= starts_at
    return :soon if joinable?(at)

    :upcoming
  end

  def rsvped?(user)
    user.present? && rsvps.exists?(user: user)
  end

  # Idempotent per user (a retried job resumes after a mid-loop failure
  # without double-pinging); the stamp is only set once every send succeeded.
  def notify_rsvps!
    return if rsvps_notified_at.present?
    return if ended?

    rsvped_users.find_each do |user|
      next if Notifications::Workshops::StartingSoon.exists?(recipient: user, record: self)

      Notifications::Workshops::StartingSoon.notify(recipient: user, record: self)
    end
    update_column(:rsvps_notified_at, Time.current)
  end

  private

    def ends_after_start
      return if starts_at.blank? || ends_at.blank?

      errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
    end

    # The job carries its scheduled start time so a pre-reschedule job no-ops;
    # moving an announced workshop to a future slot re-announces it.
    def schedule_rsvp_notifications
      update_column(:rsvps_notified_at, nil) if rsvps_notified_at.present? && starts_at.future?

      Workshop::NotifyRsvpsJob
        .set(wait_until: starts_at - JOIN_WINDOW)
        .perform_later(id, starts_at.iso8601)
    end
end
