class My::DevToolsController < ApplicationController
  # Convenience endpoints for local development only — never reachable in
  # production. Each action 404s outside of dev to keep the surface area tight.

  def pretend_idv
    return head :not_found unless Rails.env.development?
    return head :unauthorized unless current_user

    current_user.apply_hca_verification_payload!(
      { "verification_status" => "verified", "ysws_eligible" => true },
      persist_with_callbacks: false
    )

    redirect_back fallback_location: user_path(current_user),
                  notice: "Dev override: pretending identity is verified."
  end
end
