class Project::MagicHappeningLetterJob < ApplicationJob
  queue_as :default
  notify_maintainers_on_exhaustion StandardError, maintainers_slack_ids: [ "U07L45W79E1" ], wait: :polynomially_longer, attempts: 3

  def perform(project)
    unless Rails.env.production?
      Rails.logger.info "we'd be sending a letter about #{project.to_global_id} (#{project.title}) if we were in prod" and return
    end
    owner = project.memberships.owner.first&.user
    return unless owner

    address = owner.addresses.first

    if owner.email.blank? || address.blank?
      Rails.logger.info "MagicHappeningLetterJob: project #{project.id} missing owner email or address, re-enqueuing job to wait for data"
      self.class.set(wait: 15.minutes).perform_later(project)
      return
    end

    response = TheseusService.create_letter_v1(
      "instant/stardance-magic-happening",
      {
        recipient_email: owner.email,
        address: address,
        idempotency_key: "stardance_magic_project_#{project.id}",
        metadata: {
          stardance_user: owner.id,
          project: project.title,
          reviewer: project.marked_fire_by&.display_name
        }
      }
    )

    if response && response[:id]
      project.update!(fire_letter_id: response[:id])
    else
      Rails.logger.error "MagicHappeningLetterJob: No letter ID returned for project #{project.id}"
    end
  rescue => e
    Rails.logger.error "MagicHappeningLetterJob: Failed to send letter for project #{project.id}: #{e.message}"
    raise e
  end
end
