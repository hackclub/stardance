# frozen_string_literal: true

class AmbassadorCostStatsService
  COST_FIELDS = {
    poster_cost_cents: "posterCost",
    referral_cost_cents: "referralCost",
    shirt_cost_cents: "shirtCost",
    admin_cost_cents: "adminCost",
    office_grant_cost_cents: "officeGrantCost",
    total_cost_cents: "total",
    average_cost_per_ambassador_cents: "averageCostPerAmbassador"
  }.freeze

  REGION_BREAKDOWN_FIELD = "ambassadorRegionBreakdown"

  class << self
    def enabled?
      access_key.present?
    end

    def sync!
      return unless enabled?

      payload = fetch_costs
      return if payload.nil?

      AmbassadorCostStat.create!(
        stat_attributes(payload).merge(synced_at: Time.current)
      )
    end

    def access_key
      ENV["STARDANCE_DATA_ACCESS_KEY"].to_s.strip
    end

    private

    def fetch_costs
      response = connection.get("api/stats/costs") do |request|
        request.headers["X-Stardance-Data-Access-Key"] = access_key
      end

      case response.status
      when 200 then response.body
      when 503 then nil
      else raise "Ambassador costs endpoint returned #{response.status}: #{response.body}"
      end
    end

    def stat_attributes(payload)
      cost_attributes(payload)
        .merge(approved_ambassadors_count: payload.fetch("totalApprovedAmbassadors").to_i)
        .merge(ambassador_region_breakdown: region_breakdown(payload))
    end

    def cost_attributes(payload)
      COST_FIELDS.to_h { |attribute, key| [ attribute, cents(payload.fetch(key)) ] }
    end

    def region_breakdown(payload)
      payload.fetch(REGION_BREAKDOWN_FIELD).to_h.transform_values(&:to_i)
    end

    def cents(value)
      (BigDecimal(value.to_s) * 100).round.to_i
    end

    def connection
      Faraday.new(url: "https://ambassador.hackclub.com") do |faraday|
        faraday.adapter Faraday.default_adapter
        faraday.response :json
      end
    end
  end
end
