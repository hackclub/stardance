class Certificates::OgImagesController < ApplicationController
  def show
    skip_authorization

    certificate = Certificate.approved.find_by(code: Certificate.normalize_code(params[:code]))
    return render_not_found if certificate.nil?

    png_data = OgImage::Certificate.new(certificate).to_png

    expires_in 1.hour, public: true
    send_data png_data, type: "image/png", disposition: "inline"
  end
end
