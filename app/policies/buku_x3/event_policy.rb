module BukuX3
  class EventPolicy < ApplicationPolicy
    def show?
      user.present? && Flipper.enabled?(:bukux3, user)
    end

    def reveal?
      show? && user.onboarded? &&
        user.has_dismissed?(VisualNovelComponent::BUKU_X3_DISMISS_THING)
    end

    def preview? = Rails.env.development?
  end
end
