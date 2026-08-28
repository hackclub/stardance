module ApiAuthenticatable
  extend ActiveSupport::Concern

  private

  def bearer_token
    request.authorization.to_s[/\ABearer (.+)\z/, 1]
  end
end
