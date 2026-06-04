# frozen_string_literal: true

class Admin::ReviewerPayoutRequestPolicy < ApplicationPolicy
  def index? = user&.admin?
  def show?  = user&.admin?
  def pay?   = user&.admin?
  def reject? = user&.admin?
end
