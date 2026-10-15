# frozen_string_literal: true

class CertificatePolicy < ApplicationPolicy
  def create?
    user.present? && user.certificate.nil? && user.certificate_eligible?
  end

  # Re-requesting is only for fixing a rejected name, and only while the
  # holder still qualifies (ship approvals can be revoked after rejection).
  def update?
    user.present? && record.user_id == user.id && record.rejected? && user.certificate_eligible?
  end

  def regenerate?
    user.present? && record.user_id == user.id && record.approved? && user.certificate_eligible?
  end

  def download?
    user.present? && user.certificate&.approved?
  end
end
