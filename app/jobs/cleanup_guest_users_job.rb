class CleanupGuestUsersJob < ApplicationJob
  queue_as :literally_whenever

  RETENTION = 30.days
  MAX_PER_RUN = 500

  def perform
    cutoff = RETENTION.ago
    scope = User.left_outer_joins(:hack_club_identity)
                .where(user_identities: { id: nil })
                .where("users.created_at < ?", cutoff)

    found = scope.count
    if found > MAX_PER_RUN
      Sentry.capture_message(
        "CleanupGuestUsersJob exceeded MAX_PER_RUN; aborting",
        level: :warning,
        extra: { found: found, max: MAX_PER_RUN, cutoff: cutoff }
      )
      return
    end

    deleted = 0
    PaperTrail.request(whodunnit: "CleanupGuestUsersJob") do
      scope.find_each(batch_size: 100) do |user|
        user.destroy
        deleted += 1
      end
    end

    Rails.logger.info("CleanupGuestUsersJob destroyed #{deleted} guests (cutoff: #{cutoff})")
  end
end
