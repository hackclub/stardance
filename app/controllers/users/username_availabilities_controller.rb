class Users::UsernameAvailabilitiesController < ApplicationController
  PRAISES = [
    "That name looks good on you.",
    "That's a good username.",
    "Nice pick!",
    "Solid choice.",
    "Niiice.",
    "Yeah, that works.",
    "Stardust-worthy.",
    "Looks great on you.",
    "Got a ring to it."
  ].freeze

  def show
    name = params[:display_name].to_s.strip
    render json: availability_for(name)
  end

  private
    def availability_for(name)
      if name.blank?
        { status: "empty", message: nil }
      elsif !name.match?(User::USERNAME_FORMAT)
        { status: "invalid", message: "Only letters, numbers, hyphens, and underscores allowed." }
      elsif name.length > User::MAX_DISPLAY_NAME_LENGTH
        { status: "too_long", message: "Keep it under #{User::MAX_DISPLAY_NAME_LENGTH} characters." }
      elsif taken?(name)
        { status: "taken", message: "Already taken — try another." }
      else
        { status: "available", message: PRAISES.sample }
      end
    end

    def taken?(name)
      if User::UsernameBloomFilter.probably_taken?(name)
        User.unscoped
            .where("LOWER(display_name) = ?", name.downcase)
            .where.not(id: current_user&.id)
            .exists?
      else
        false
      end
    end
end
