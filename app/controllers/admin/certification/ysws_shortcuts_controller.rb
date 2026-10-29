class Admin::Certification::YswsShortcutsController < Admin::Certification::ApplicationController
  before_action :authorize_shortcuts

  def update
    raw = params[:shortcuts]
    settings = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
    errors = ::Certification::YswsShortcuts.errors(settings)
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    preference = nil
    current_user.with_lock do
      preference = current_user.preference || current_user.create_preference!
      preference.lock!
      previous = preference.ysws_shortcuts
      preference.update!(ysws_shortcuts: settings)
      if previous != settings
        # Attach to the user so this is also accessible in their audit history.
        ::PaperTrail::Version.create!(
          item: current_user,
          event: "ysws_shortcuts_updated",
          whodunnit: user_for_paper_trail.to_s,
          object_changes: { ysws_shortcuts: [ previous, settings ] }
        )
      end
    end
    render json: { shortcuts: preference.ysws_shortcuts }
  end

  private

  def authorize_shortcuts
    authorize ::Certification::Ysws, :update?
    head :forbidden unless Flipper.enabled?(:ysws_review_shortcuts, current_user)
  end
end
