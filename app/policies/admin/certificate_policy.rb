# frozen_string_literal: true

class Admin::CertificatePolicy < ApplicationPolicy
  def index? = user&.admin?
  def update? = user&.admin?
end
