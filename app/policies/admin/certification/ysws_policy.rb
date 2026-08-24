class Admin::Certification::YswsPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.has_role?(:guardian_of_integrity)
  end

  def show?
    index?
  end

  def dashboard?
    index?
  end

  def update?
    index?
  end

  def report_fraud?
    index?
  end

  # Reversing a decided review is destructive and admin-only: guardians of
  # integrity can review, but cannot undo a completed review. Returned reviews
  # are out of scope — #return_to_ship_cert also opens a recert
  # Certification::Ship and hands the external cert id to it, and undo can't
  # put that back.
  def undo?
    user&.admin? && record.reviewed_at? && record.returned_at.nil?
  end

  def unclaim?
    user.present? && index? && record.pending? && record.claimed_by?(user)
  end

  def resync?
    index?
  end
end
