# frozen_string_literal: true

class AmbassadorCostStatsService
  COST_FIELDS = {
    poster_cost_cents: "posterCost",
    poster_cost_us_cents: "posterCostUS",
    referral_cost_cents: "referralCost",
    referral_cost_us_cents: "referralCostUS",
    shirt_cost_cents: "shirtCost",
    shirt_cost_us_cents: "shirtCostUS",
    admin_cost_cents: "adminCost",
    admin_cost_us_cents: "adminCostUS",
    office_grant_cost_cents: "officeGrantCost",
    office_grant_cost_us_cents: "officeGrantCostUS",
    total_cost_cents: "total",
    total_cost_us_cents: "totalCostUS",
    average_cost_per_ambassador_cents: "averageCostPerAmbassador",
    average_cost_us_cents: "averageCostUS"
  }.freeze

  COUNT_FIELDS = {
    total_referrals: "totalReferrals",
    total_referrals_us: "totalReferralsUS",
    total_completed_referrals: "totalCompletedReferrals",
    total_completed_referrals_us: "totalCompletedReferralsUS"
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
        .merge(count_attributes(payload))
        .merge(approved_ambassadors_count: payload.fetch("totalApprovedAmbassadors").to_i)
        .merge(ambassador_region_breakdown: region_breakdown(payload))
    end

    def cost_attributes(payload)
      COST_FIELDS.to_h { |attribute, key| [ attribute, cents(payload.fetch(key)) ] }
    end

    def count_attributes(payload)
      COUNT_FIELDS.to_h { |attribute, key| [ attribute, payload.fetch(key).to_i ] }
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
