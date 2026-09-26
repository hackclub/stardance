class Api::V1::Certification::BaseController < Api::V1::BaseController
  private

  def credential_api_keys
    Array.wrap(Rails.application.credentials.dig(:certification_shipwrights, :api_keys))
  end
end
