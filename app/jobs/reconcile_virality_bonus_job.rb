class ReconcileViralityBonusJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::Deadlocked, wait: 2.seconds, attempts: 3

  def perform(project_id)
    project = Project.find_by(id: project_id)
    return unless project

    PaperTrail.request(whodunnit: "system:virality") do
      Virality::ReconcileBonus.new(project).call
    end
  end
end
