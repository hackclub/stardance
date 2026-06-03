class IdentitiesController < ApplicationController
  def hackatime
    authorize :identity

    auth = request.env["omniauth.auth"]
    access_token = auth&.credentials&.token.to_s

    uid = HackatimeService.fetch_authenticated_user(access_token) if access_token.present?

    if uid.blank?
      redirect_to return_path, alert: "Could not determine Hackatime user. Try again."
      return
    end

    identity = current_user.identities.find_or_initialize_by(provider: "hackatime")
    identity.uid = uid
    identity.access_token = access_token if access_token.present?
    identity.save!

    result = current_user.try_sync_hackatime_data!(force: true)
    total_seconds = result&.dig(:projects)&.values&.sum || 0

    track_event "hackatime_linked", { user_id: current_user.id }
    redirect_to return_path, notice: "Hackatime linked!"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Hackatime identity save failed: #{e.record.errors.full_messages.join(", ")}")
    alert = if e.record.errors.of_kind?(:uid, :taken)
      "It seems like your Hackatime is already linked to a different Stardance account. Please contact support!"
    else
      "Failed to link Hackatime: #{e.record.errors.full_messages.first}"
    end

    redirect_to return_path, alert:
  end

  private

  # OmniAuth captures the page the user came from (or any `origin` form/query
  # param) and exposes it as `omniauth.origin` on the callback. Only honor
  # relative paths so this can't be turned into an open redirect.
  def return_path
    origin = request.env["omniauth.origin"].to_s
    return home_path if origin.blank?
    return home_path unless origin.start_with?("/") && !origin.start_with?("//")
    origin
  end
end
