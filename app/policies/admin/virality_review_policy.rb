class Admin::ViralityReviewPolicy < ApplicationPolicy
  def index? = ViralityDecision.reviewer?(user)
  def show? = ViralityDecision.reviewer?(user)
  def create? = ViralityDecision.reviewer?(user)
  def cancel? = ViralityDecision.reviewer?(user)
  def triage? = ViralityDecision.reviewer?(user)
  def batch? = ViralityDecision.reviewer?(user)
end
