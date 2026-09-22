# frozen_string_literal: true

module DiscoverRail
  class CertificateWidget < BaseWidget
    register_as :certificate

    # Deferred: the approved-hours aggregate runs in the lazy frame request,
    # not on the synchronous page render (and never when the rail is hidden).
    def deferred?
      true
    end

    def deferred_frame_id
      "discover_rail_certificate"
    end

    def deferred_path_helper
      :certificate_home_discover_rail_path
    end

    def render?
      user.present? && own_context?
    end

    def certificate
      @certificate ||= user.certificate
    end

    def hours
      @hours ||= user.approved_hours
    end

    def required
      Certificate::REQUIRED_APPROVED_HOURS
    end

    def eligible?
      hours >= required
    end

    private

    # On profile pages the rail context carries the profile owner. Only
    # advertise certificate progress on the viewer's own profile.
    def own_context?
      profile_user = context[:profile_user]
      profile_user.nil? || profile_user == user
    end
  end
end
