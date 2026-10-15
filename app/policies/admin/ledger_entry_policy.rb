class Admin::LedgerEntryPolicy < ApplicationPolicy
  def index? = user&.admin?
end
