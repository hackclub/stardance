require "securerandom"

module Raffle
  class Participant < ApplicationRecord
    has_paper_trail

    belongs_to :user, class_name: "::User", optional: true
    belongs_to :signup_week, class_name: "Raffle::Week", optional: true
    has_many :referrals, class_name: "Raffle::Referral", dependent: :destroy

    enum :age_group, { teen: "teen", adult: "adult" }, prefix: :age_group

    before_validation :assign_code, on: :create

    validates :code, presence: true, uniqueness: true
    validates :user_id, presence: true, uniqueness: { allow_nil: true }, if: :age_group_teen?
    validates :github_uid, presence: true, uniqueness: { allow_nil: true }, if: :age_group_adult?
    validates :github_login, presence: true, if: :age_group_adult?
    validate :has_identity

    def self.generate_unique_code
      alphabet = "abcdefghjkmnpqrstuvwxyz23456789"
      100.times do
        candidate = 5.times.map { alphabet[SecureRandom.random_number(alphabet.length)] }.join
        return candidate unless exists?(code: candidate)
      end
      raise "could not generate a unique raffle code"
    end

    def self.find_or_enroll!(user)
      participant = find_or_initialize_by(user: user)
      if participant.new_record?
        participant.age_group = :teen
        participant.signup_week = Raffle::Week.current
        participant.save!
      end
      participant
    end

    def self.from_github(auth)
      uid = auth.uid.to_s
      info = auth.info
      login = info&.nickname.to_s.strip.presence || "github-#{uid}"

      participant = find_or_initialize_by(github_uid: uid)
      participant.github_login = login
      participant.github_avatar_url = info&.image
      participant.age_group = :adult
      participant.save!
      participant
    end

    def display_name
      age_group_teen? ? user&.display_name : github_login
    end

    def referral_url(channel = :web)
      prefix = channel == :discord ? "d" : "r"
      "https://stardance.space/#{prefix}-#{code}"
    end

    def entry_count(week)
      return 0 unless week && eligible?
      return 0 if age_group_teen? && !hca_linked?

      base = (age_group_teen? && signup_week_id == week.id) ? 1 : 0
      referral_entries = referrals.status_verified.where(credited_week_id: week.id).count * 20
      base + referral_entries
    end

    def eligible?
      eligible
    end

    def hca_linked?
      return true unless age_group_teen?
      user&.hca_linked?
    end

    def pending_referrals
      referrals.status_pending.order(created_at: :desc)
    end

    def visible_referrals
      referrals.where.not(status: :self_referral)
    end

    private

    def assign_code
      self.code ||= self.class.generate_unique_code
    end

    def has_identity
      return if user_id.present? || github_uid.present?
      errors.add(:base, "must have either a user or GitHub identity")
    end
  end
end
