# frozen_string_literal: true

# borrowed code from the summer of making
module Shop
  module Regionalizable
    extend ActiveSupport::Concern

    REGIONS = {
      "US" => { name: "United States", countries: [ "US" ] },
      "EU" => { name: "EU", countries: [ "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE" ] },
      "UK" => { name: "United Kingdom", countries: [ "GB" ] },
      "IN" => { name: "India", countries: [ "IN" ] },
      "CA" => { name: "Canada", countries: [ "CA" ] },
      "AU" => { name: "Australia", countries: [ "AU", "NZ" ] },
      "XX" => { name: "Rest of World", countries: [] } # Special case - everything else
    }.freeze

    REGION_CODES = REGIONS.keys.freeze

    included do
      # Define scope methods for each region
      REGION_CODES.each do |code|
        column = "enabled_#{code.downcase}".to_sym
        scope :"enabled_in_#{code.downcase}", -> { where(column => true) }
        scope :"disabled_in_#{code.downcase}", -> { where(column => [ false, nil ]) }
      end
    end

    def any_region_enabled?
      return @_any_region_enabled if defined?(@_any_region_enabled)
      @_any_region_enabled = REGION_CODES.any? { |code| send("enabled_#{code.downcase}") }
    end

    def enabled_in_region?(region_code)
      return false unless REGION_CODES.include?(region_code.upcase)

      return true unless any_region_enabled?

      region_value = send("enabled_#{region_code.downcase}")

      # If explicitly set for this region, use that value
      return region_value unless region_value.nil?

      # Only fall back to XX (Rest of World) if region is not explicitly set
      enabled_xx
    end

    def enabled_region_codes
      @_enabled_region_codes ||= REGION_CODES.select { |code| enabled_in_region?(code) }
    end

    def price_for_region(region_code)
      apply_sale_discount(base_price_for_region(region_code))
    end

    def base_price_for_region(region_code)
      region_code = region_code.upcase
      region_code = "XX" unless REGION_CODES.include?(region_code)

      # Get region-specific USD offset, falling back to XX offset if not set
      region_usd_offset = send("usd_offset_#{region_code.downcase}")
      usd_offset = region_usd_offset.present? ? region_usd_offset : (send("usd_offset_xx") || 0)

      hacker_multiplier = 0.5 + (1.0 - (hacker_score || 50) / 100.0)
      tickets_per_dollar = Rails.configuration.game_constants.tickets_per_dollar

      ((ticket_cost || 0) + (usd_offset * tickets_per_dollar * hacker_multiplier)).round
    end

    private

    def apply_sale_discount(price)
      percentage = current_sale_percentage.to_i
      return price unless percentage.between?(1, 100)

      # Multiply before dividing so 45% off 100 is exactly 55, not 55.000001 ceiled to 56.
      (price * (100 - percentage)).fdiv(100).ceil
    end

    def self.country_to_region(country_code)
      return "XX" if country_code.blank?

      REGIONS.each do |region_code, config|
        next if region_code == "XX" # Skip "rest of world" in initial search
        return region_code if config[:countries].include?(country_code.upcase)
      end

      "XX" # Default to "rest of world"
    end

    def self.region_name(region_code)
      REGIONS.dig(region_code.upcase, :name) || "Unknown Region"
    end

    def self.countries_for_region(region_code)
      REGIONS.dig(region_code.upcase, :countries) || []
    end

    TIMEZONE_TO_COUNTRY = TZInfo::Country.all.each_with_object({}) do |country, map|
      country.zone_identifiers.each { |tz_id| map[tz_id] ||= country.code }
    end.freeze

    def self.timezone_to_region(timezone)
      return "XX" if timezone.blank?
      country_to_region(TIMEZONE_TO_COUNTRY[timezone])
    end
  end
end
