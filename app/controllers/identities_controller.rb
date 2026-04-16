class IdentitiesController < ApplicationController
  def hackatime
    unless current_user
      redirect_to root_path, alert: "Please log in first."
      return
    end

    auth = request.env["omniauth.auth"]
    access_token = auth&.credentials&.token.to_s

    uid = HackatimeService.fetch_authenticated_user(access_token) if access_token.present?

    if uid.blank?
      redirect_to kitchen_path, alert: "Could not determine Hackatime user. Try again."
      return
    end

    identity = current_user.identities.find_or_initialize_by(provider: "hackatime")
    identity.uid = uid
    identity.access_token = access_token if access_token.present?
    identity.save!
    current_user.complete_tutorial_step! :setup_hackatime

    FunnelTrackerService.track(
      event_name: "hackatime_linked",
      user: current_user
    )

    result = current_user.try_sync_hackatime_data!(force: true)
    total_seconds = result&.dig(:projects)&.values&.sum || 0

    # if total_seconds > 0
    #   duration = helpers.distance_of_time_in_words(total_seconds)
    #   tutorial_message [
    #     "Waouh! You already have #{duration} tracked on Hackatime — well done!",
    #     "Now we will create a project..."
    #   ]
    # else
    #   tutorial_message [
    #     "Oh, it would appear that Hackatime is linked, but you don't have any time tracked yet.",
    #     "Don't worry — just install the Hackatime extension in your code editor.",
    #     "And then cook up tasty projects here, earn cookies, and get free rewards!"
    #   ]
    # end

    redirect_to kitchen_path, notice: "Hackatime linked!"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Hackatime identity save failed: #{e.record.errors.full_messages.join(", ")}")
    alert = if e.record.errors.of_kind?(:uid, :taken)
      "It seems like your Hackatime is already linked to a different Stardance account. Please contact support!"
    else
      "Failed to link Hackatime: #{e.record.errors.full_messages.first}"
    end

    redirect_to kitchen_path, alert:
  end
end
