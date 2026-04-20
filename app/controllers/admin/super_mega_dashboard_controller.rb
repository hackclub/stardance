# frozen_string_literal: true

module Admin
  class SuperMegaDashboardController < Admin::ApplicationController
    include SuperMegaDashboard::FraudStats
    include SuperMegaDashboard::FulfillmentStats
    include SuperMegaDashboard::SupportStats
    include SuperMegaDashboard::ShipwrightsStats
    include SuperMegaDashboard::YswsReviewStats
    include SuperMegaDashboard::MiscStats
    include SuperMegaDashboard::NpsStats

    CACHE_KEYS = %w[
      super_mega_fraud_stats
      super_mega_ban_trend
      super_mega_order_trend
      super_mega_report_trend
      joe_fraud_stats
      super_mega_payouts
      super_mega_fulfillment
      super_mega_fulfillment_trend
      super_mega_order_states_trend
      shop_suggestion_llm_results
      super_mega_support
      super_mega_support_vibes
      super_mega_support_graph
      super_mega_voting
      super_mega_ysws_review_v2
      super_mega_ship_certs_raw
      sw_vibes_data
      super_mega_funnel_stats
      super_mega_nps_stats
      super_mega_nps_vibes
      super_mega_hcb_stats
      super_mega_hcb_stats_v2
    ].freeze

    SECTIONS = {
      "funnel"             => { loaders: %i[load_funnel_stats],           partial: "admin/super_mega_dashboard/sections/funnel" },
      "nps"                => { loaders: %i[load_nps_stats load_nps_vibes_stats], partial: "admin/super_mega_dashboard/sections/nps" },
      "hcb"                => { loaders: %i[load_hcb_expenses],           partial: "admin/super_mega_dashboard/sections/hcb" },
      "fraud"              => { loaders: %i[load_fraud_stats load_fraud_happiness_data], partial: "admin/super_mega_dashboard/sections/fraud" },
      "payouts"            => { loaders: %i[load_payouts_stats],          partial: "admin/super_mega_dashboard/sections/payouts" },
      "fulfillment"        => { loaders: %i[load_fulfillment_stats],      partial: "admin/super_mega_dashboard/sections/fulfillment" },
      "shipwrights"        => { loaders: %i[load_ship_certs_stats load_sw_vibes_stats load_sw_vibes_history load_make_their_day_data], partial: "admin/super_mega_dashboard/sections/shipwrights" },
      "support"            => { loaders: %i[load_support_stats load_support_vibes_stats load_support_graph_data], partial: "admin/super_mega_dashboard/sections/support" },
      "ysws_review"        => { loaders: %i[load_ysws_review_stats],      partial: "admin/super_mega_dashboard/sections/ysws_review" },
      "voting"             => { loaders: %i[load_voting_stats],           partial: "admin/super_mega_dashboard/sections/voting" },
      "community"          => { loaders: %i[load_community_engagement_stats], partial: "admin/super_mega_dashboard/sections/community" },
      "pyramid_flavortime" => { loaders: %i[load_flavortime_summary load_pyramid_scheme_stats], partial: "admin/super_mega_dashboard/sections/pyramid_flavortime" }
    }.freeze

    def index
      authorize :admin, :access_super_mega_dashboard?
    end

    def load_section
      authorize :admin, :access_super_mega_dashboard?

      section = params[:section]
      config = SECTIONS[section]

      unless config
        render plain: "Unknown section", status: :bad_request
        return
      end

      config[:loaders].each { |loader| send(loader) }
      render partial: config[:partial], layout: false
    end

    def clear_cache
      authorize :admin, :access_super_mega_dashboard?

      CACHE_KEYS.each { |key| Rails.cache.delete(key) }

      flash[:notice] = "Cache cleared successfully."
      redirect_to admin_super_mega_dashboard_path
    end

    def refresh_nps_vibes
      authorize :admin, :access_super_mega_dashboard?

      Rails.cache.delete("super_mega_nps_vibes")
      payload = build_nps_vibes_from_airtable(limit: 500)

      Rails.cache.write("super_mega_nps_vibes", payload)
      if payload.is_a?(Hash) && payload[:error].present?
        flash[:alert] = payload[:error]
      else
        flash[:notice] = "NPS vibes revibed."
      end

      redirect_to admin_super_mega_dashboard_path
    end
  end
end
