class ProcessViralityDecisionJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::Deadlocked, wait: 2.seconds, attempts: 3

  def perform(decision_id)
    decision = ViralityDecision.find_by(id: decision_id)
    return unless decision&.status == "scheduled"

    if decision.process_at > Time.current
      self.class.set(wait_until: decision.process_at).perform_later(decision.id)
    else
      decision.process!
    end
  rescue ActiveRecord::Deadlocked
    raise
  rescue StandardError => error
    decision&.fail!("Processing failed (#{error.class.name}). No decision was applied; review and schedule again.")
    raise
  end
end
