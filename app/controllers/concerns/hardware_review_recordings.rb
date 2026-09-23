# frozen_string_literal: true

# Lapse + Lookout recordings for a hardware project, shared by the T1 and T2 reviews.
module HardwareReviewRecordings
  extend ActiveSupport::Concern

  # Provider URLs expire after ~1h, so keep this short.
  RECORDINGS_CACHE_TTL = 1.minute

  private

  def lapse_timelapses_for(project, owner)
    Rails.cache.fetch([ "hardware_review_recordings", "lapse", project.id ], expires_in: RECORDINGS_CACHE_TTL) do
      LapseService.timelapses_for_project(
        hackatime_user_id: owner&.hackatime_identity&.uid,
        project_keys: project.hackatime_keys
      )
    end
  end

  def lookout_recordings_for(project)
    Rails.cache.fetch([ "hardware_review_recordings", "lookout", project.id ], expires_in: RECORDINGS_CACHE_TTL) do
      LookoutService.recordings_for_project(project)
    end
  end
end
