class RecoverViralityDecisionsJob < ApplicationJob
  queue_as :default

  def perform
    # Durable recovery if enqueueing failed after the database commit. Repeated
    # deliveries are harmless: processing rechecks the status under a row lock.
    ViralityDecision.due.find_each do |decision|
      ProcessViralityDecisionJob.perform_later(decision.id)
    end
  end
end
