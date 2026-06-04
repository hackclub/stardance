# frozen_string_literal: true

class Admin::Certification::MystatsPolicy < ApplicationPolicy
  def show? = user&.can_review?
  def create_payout_request? = user&.can_review?
end
