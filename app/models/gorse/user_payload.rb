# frozen_string_literal: true

class Gorse::UserPayload
  def initialize(user)
    @user = user
  end

  def to_h
    {
      UserId: Gorse::Ids.user(user),
      Labels: labels,
      Comment: user.display_name.to_s
    }
  end

  private
    attr_reader :user

    def labels
      Gorse::Labels.cast(
        interests: user.interests,
        regions: user.regions,
        experience_level: user.experience_level,
        shop_region: user.shop_region,
        verification_status: user.verification_status,
        ysws_eligible: user.ysws_eligible?
      )
    end
end
