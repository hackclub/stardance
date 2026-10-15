module Admin
  # The all-queues dashboard. Sections load lazily over `section`, each behind
  # its own cache key, so one slow or dead data source can't hold up the page
  # or take the rest of it down with it.
  class MegaDashboardController < Admin::ApplicationController
    CACHE_NAMESPACE = "mega_dashboard".freeze
    CACHE_TTL = 5.minutes
    QueueStats = MegaDashboard::QueueStats
    # Deliberately outside CACHE_NAMESPACE so "Clear cache" doesn't discard an
    # expensive LLM result.
    NPS_VIBES_CACHE_KEY = "mega_dashboard_nps_vibes".freeze

    def show
      authorize :mega_dashboard
      @period = QueueStats::PERIODS.key?(params[:period].to_s) ? params[:period].to_s : QueueStats::DEFAULT_PERIOD
      @queues = MegaDashboard::Queue.all
    end

    def section
      authorize :mega_dashboard
      @period = QueueStats::PERIODS.key?(params[:period].to_s) ? params[:period].to_s : QueueStats::DEFAULT_PERIOD

      case params[:section]
      when "overview" then render_overview
      when "waterfall" then render_waterfall
      when "jelly" then render_jelly
      when "votes" then render_votes
      when "nps" then render_nps
      when "money" then render_money
      when "fulfillment" then render_fulfillment
      when /\Aqueue:(?<key>.+)\z/ then render_queue($~[:key])
      else head :bad_request
      end
    end

    # Themes cost an Airtable page plus an LLM call, so they're only ever built
    # on request and stored outside the section cache the clear button sweeps.
    def refresh_nps_vibes
      authorize :mega_dashboard, :clear_cache?

      payload = MegaDashboard::NpsStats.new.build_vibes
      Rails.cache.write(NPS_VIBES_CACHE_KEY, payload, expires_in: 30.days)

      redirect_to admin_mega_dashboard_path, notice: payload[:error].presence || "NPS themes refreshed."
    end

    def clear_cache
      authorize :mega_dashboard
      Rails.cache.delete_matched("#{CACHE_NAMESPACE}/*")
      redirect_to admin_mega_dashboard_path, notice: "Dashboard cache cleared."
    end

    private

    def render_queue(key)
      @queue = MegaDashboard::Queue.find(key)
      return head :not_found unless @queue

      @payload = cached("queue/#{@queue.key}/#{@period}") do
        stats = QueueStats.new(@queue, period: @period)
        { tiles: stats.tiles, metrics: stats.metrics, chart_data: stats.chart_data }
      end
      render partial: "admin/mega_dashboard/sections/queue", layout: false
    rescue StandardError => e
      render_section_error("queue:#{key}", e)
    end

    def render_overview
      @rows = cached("overview") do
        MegaDashboard::QueueOverview.rows.map do |row|
          {
            key: row.queue.key, label: row.label, url: row.url, depth: row.depth,
            arrivals: row.arrivals, decisions: row.decisions,
            net: row.net, days_to_clear: row.days_to_clear, overdue: row.overdue,
            oldest_wait_hours: row.oldest_wait_hours,
            median_decision_hours: row.median_decision_hours, health: row.health,
            error: row.error
          }
        end
      end

      render partial: "admin/mega_dashboard/sections/overview", layout: false
    rescue StandardError => e
      render_section_error("overview", e)
    end

    def render_fulfillment
      @fulfillment = cached("fulfillment") { MegaDashboard::FulfillmentStats.new.to_h }

      render partial: "admin/mega_dashboard/sections/fulfillment", layout: false
    rescue StandardError => e
      render_section_error("fulfillment", e)
    end

    def render_money
      @money = cached("money") { MegaDashboard::MoneyStats.new.to_h }

      render partial: "admin/mega_dashboard/sections/money", layout: false
    rescue StandardError => e
      render_section_error("money", e)
    end

    def render_nps
      @nps = cached("nps") { MegaDashboard::NpsStats.new.headline }
      @nps_vibes = Rails.cache.read(NPS_VIBES_CACHE_KEY)

      render partial: "admin/mega_dashboard/sections/nps", layout: false
    rescue StandardError => e
      render_section_error("nps", e)
    end

    def render_votes
      @votes = cached("votes/#{@period}") { MegaDashboard::VoteStats.new(period: @period).to_h }

      render partial: "admin/mega_dashboard/sections/votes", layout: false
    rescue StandardError => e
      render_section_error("votes", e)
    end

    def render_jelly
      @jelly = cached("jelly/#{@period}") { MegaDashboard::JellyStats.new(period: @period).to_h }

      render partial: "admin/mega_dashboard/sections/jelly", layout: false
    rescue StandardError => e
      render_section_error("jelly", e)
    end

    def render_waterfall
      @waterfall = cached("waterfall/#{@period}") do
        MegaDashboard::Waterfall.new(period: @period).to_h
      end

      render partial: "admin/mega_dashboard/sections/waterfall", layout: false
    rescue StandardError => e
      render_section_error("waterfall", e)
    end

    def cached(key, &block)
      Rails.cache.fetch("#{CACHE_NAMESPACE}/#{key}", expires_in: CACHE_TTL, &block)
    end

    def render_section_error(section, error)
      Rails.logger.error("[MegaDashboard] #{section} failed (#{error.class}): #{error.message}")
      @section_error = error.message
      @frame_id = frame_id_for(section)
      render partial: "admin/mega_dashboard/section_error", layout: false
    end

    def frame_id_for(section) = "mega-dash-#{section.tr(':', '-')}"
  end
end
