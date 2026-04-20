class OgImagesController < ApplicationController
  skip_before_action :verify_authenticity_token

  STATIC_PAGES = {
    "home" => -> { OgImage::Home.new },
    "start" => -> { OgImage::Start.new },
    "explore" => -> { OgImage::Explore.new },
    "gallery" => -> { OgImage::Gallery.new },
    "extensions" => -> { OgImage::Extensions.new },
    "shop" => -> { OgImage::Shop.new }
  }.freeze

  def show
    skip_authorization

    page = params[:page]
    generator = STATIC_PAGES[page]

    unless generator
      render plain: "Unknown page: #{page}", status: :not_found
      return
    end

    png_data = generator.call.to_png

    expires_in 1.day, public: true
    send_data png_data, type: "image/png", disposition: "inline"
  end
end
