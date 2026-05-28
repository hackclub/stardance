# frozen_string_literal: true

class StarImageInputComponent < ViewComponent::Base
  VARIANTS = (1..5).to_a.freeze

  IDLE_PRIMARY = "Drag an image"
  IDLE_SECONDARY = "or click to choose a file"

  attr_reader :variant, :name, :id, :accept, :primary_text, :secondary_text,
              :direct_upload, :current_url, :current_alt, :required

  def initialize(variant: 1, name: nil, id: nil, accept: "image/*",
                 primary_text: IDLE_PRIMARY, secondary_text: IDLE_SECONDARY,
                 direct_upload: false, current_url: nil, current_alt: "",
                 required: false)
    v = variant.to_i
    raise ArgumentError, "variant must be one of #{VARIANTS.inspect}, got #{variant.inspect}" unless VARIANTS.include?(v)

    @variant = v
    @name = name
    @id = id
    @accept = accept
    @primary_text = primary_text
    @secondary_text = secondary_text
    @direct_upload = direct_upload
    @current_url = current_url
    @current_alt = current_alt
    @required = required
  end

  def initial_state
    current_url.present? ? "loaded" : "idle"
  end

  def initial_primary_text
    current_url.present? ? "Click to replace" : primary_text
  end

  def initial_secondary_text
    current_url.present? ? "" : secondary_text
  end

  def frame_classes
    "star-image-input__frame star-border star-border--variant-#{variant}"
  end

  # Mirrors Rails' `file_field(direct_upload: true)` — points the hidden
  # `<input type="file">` at the Active Storage direct-uploads endpoint so
  # large files (project banners, ship banners) go straight to S3 instead of
  # round-tripping through the Rails server.
  def input_data_attributes
    attrs = {
      "star-image-input-target": "input",
      action: "change->star-image-input#fileSelected"
    }
    attrs["direct-upload-url"] = helpers.rails_direct_uploads_url if direct_upload
    attrs
  end
end
