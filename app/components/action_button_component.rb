# frozen_string_literal: true

class ActionButtonComponent < ViewComponent::Base
  SIZES = %i[small large].freeze
  VARIANTS = %i[primary secondary destructive].freeze
  SURFACES = %i[dark light].freeze

  attr_reader :text, :size, :variant, :surface, :icon, :leading_icon,
              :type, :href, :method, :disable_with, :disabled, :html_options

  def initialize(
    text: nil,
    size: :large,
    variant: :primary,
    surface: :dark,
    icon: nil,
    leading_icon: nil,
    type: :submit,
    href: nil,
    method: nil,
    disable_with: nil,
    disabled: false,
    **html_options
  )
    @size = normalize(:size, size, SIZES)
    @variant = normalize(:variant, variant, VARIANTS)
    @surface = normalize(:surface, surface, SURFACES)

    if @variant == :destructive && @size != :small
      raise ArgumentError, "variant :destructive is only available on size: :small"
    end

    @text = text
    @icon = icon
    @leading_icon = leading_icon
    @type = type
    @href = href
    @method = method
    @disable_with = disable_with
    @disabled = disabled
    @html_options = html_options
  end

  def root_classes
    class_names(
      "action-btn",
      "action-btn--#{size}",
      "action-btn--#{variant}",
      { "action-btn--light-bg" => surface == :light },
      { "action-btn--disabled" => disabled },
      html_options[:class]
    )
  end

  def shared_attributes
    attrs = html_options.except(:class).merge(class: root_classes)
    # `disabled: :soft` keeps the disabled styling but uses aria-disabled
    # instead of the native attribute, so the control still receives
    # hover/focus events (e.g. to show a tooltip explaining why it's disabled).
    if disabled == :soft
      attrs["aria-disabled"] = "true"
    elsif disabled
      attrs[:disabled] = true
    end
    attrs
  end

  def button_attributes
    attrs = shared_attributes
    if disable_with.present? && type == :submit
      attrs[:data] = (attrs[:data] || {}).merge(turbo_submits_with: disable_with)
    end
    attrs
  end

  def link_attributes
    attrs = shared_attributes
    if method.present? && method.to_sym != :get
      attrs[:data] = (attrs[:data] || {}).merge(turbo_method: method)
    end
    attrs
  end

  def link?
    href.present?
  end

  def display_text
    text || ""
  end

  def leading_icon_tag
    render_icon(leading_icon, "action-btn__icon action-btn__icon--leading")
  end

  def trailing_icon_tag
    render_icon(icon, "action-btn__icon action-btn__icon--trailing")
  end

  private

  def render_icon(source, classes)
    return nil if source.blank?
    return helpers.inline_svg_tag(source, class: classes, aria: { hidden: true }) if source.end_with?(".svg")
    helpers.image_tag(source, class: classes, "aria-hidden": true)
  end

  def normalize(name, value, allowed)
    symbolized = value.to_sym
    return symbolized if allowed.include?(symbolized)

    raise ArgumentError,
          "#{name} must be one of #{allowed.join(', ')}, got #{value.inspect}"
  end
end
