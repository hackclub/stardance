module OutpostEmailing
  extend ActiveSupport::Concern

  # The referral token that triggers the Outpost email (hitting `/outpost`).
  OUTPOST_REF = "outpost".freeze
  # Marker cookie set when a logged-out visitor hits `/outpost`, so the email
  # fires once they sign in.
  OUTPOST_PENDING_COOKIE = :outpost_email_pending

  included do
    before_action :handle_outpost_email
  end

  private

  def handle_outpost_email
    return unless Flipper.enabled?(:outpost_email)

    if params[:ref] == OUTPOST_REF
      mark_outpost_visit
      # Signed-in visitors get the email and go straight to the guide. Logged-out
      # visitors stay on the landing page to sign up first; their email and any
      # redirect are deferred until they sign in.
      redirect_to guide_path(:outpost) if current_user
      return
    end

    deliver_pending_outpost_email
  end

  def mark_outpost_visit
    if current_user
      current_user.deliver_outpost_email!
    else
      cookies[OUTPOST_PENDING_COOKIE] = { value: "1", expires: 30.days.from_now, same_site: :lax }
    end
  end

  # A visitor who hit `/outpost` while logged out gets the email on their first
  # request once signed in; `deliver_outpost_email!` keeps it to exactly once.
  def deliver_pending_outpost_email
    return if cookies[OUTPOST_PENDING_COOKIE].blank?
    # Keep the marker until there's a real recipient (guests have no email yet).
    return if current_user.nil? || current_user.email.blank?

    current_user.deliver_outpost_email!
    cookies.delete(OUTPOST_PENDING_COOKIE)
  end
end
