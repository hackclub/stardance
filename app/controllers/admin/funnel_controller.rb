# frozen_string_literal: true

module Admin
  class FunnelController < Admin::ApplicationController
    layout false

    FUNNEL_STEPS = %w[
      onboarding_started
      onboarding_experience_selected
      onboarding_interests_selected
      onboarding_referral_submitted
      onboarding_completed
      project_created
      hackatime_linked
      devlog_posted
      order_placed
      project_shipped
    ].freeze

    SANKEY_STEPS = %w[
      onboarding_completed
      project_created
      hackatime_linked
      devlog_posted
      order_placed
      project_shipped
    ].freeze

    def show
      authorize :admin, :index?

      counts = live_counts
      transitions = live_transitions

      @funnel_steps = FUNNEL_STEPS.map { |step| { name: step, count: counts[step] || 0 } }
      @sankey_nodes, @sankey_links = build_sankey(transitions)
    end

    private

    def live_counts
      Rails.cache.fetch("admin_funnel_counts", expires_in: 5.minutes) do
        Ahoy::Event
          .where(name: FUNNEL_STEPS)
          .group(:name)
          .distinct
          .count(:user_id)
      end
    end

    def live_transitions
      Rails.cache.fetch("admin_funnel_transitions", expires_in: 5.minutes) do
        fetch_transitions
      end
    end

    def fetch_transitions
      sql = <<~SQL
        WITH user_steps AS (
          SELECT user_id, name,
                 ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY time) as step_order
          FROM ahoy_events
          WHERE name IN (#{SANKEY_STEPS.map { |s| Ahoy::Event.connection.quote(s) }.join(",")})
            AND user_id IS NOT NULL
        ),
        transitions AS (
          SELECT a.name as source, b.name as target, a.user_id
          FROM user_steps a
          JOIN user_steps b ON a.user_id = b.user_id AND b.step_order = a.step_order + 1
          WHERE a.name != b.name
        )
        SELECT source, target, COUNT(DISTINCT user_id) as users
        FROM transitions
        GROUP BY source, target
        ORDER BY users DESC
      SQL

      Ahoy::Event.connection.select_all(sql).map do |row|
        { source: row["source"], target: row["target"], value: row["users"].to_i }
      end
    end

    def build_sankey(transitions)
      forward_steps = SANKEY_STEPS.each_with_index.to_h
      forward_links = transitions.select do |t|
        s = forward_steps[t[:source]]
        d = forward_steps[t[:target]]
        s && d && d > s
      end

      outflows = {}
      inflows = {}
      forward_links.each do |l|
        outflows[l[:source]] = (outflows[l[:source]] || 0) + l[:value]
        inflows[l[:target]] = (inflows[l[:target]] || 0) + l[:value]
      end

      drop_nodes = []
      drop_links = []
      SANKEY_STEPS.each do |step|
        node_total = [ outflows[step] || 0, inflows[step] || 0 ].max
        out_total = outflows[step] || 0
        dropout = node_total - out_total
        next unless dropout > 0

        drop_name = "drop_after_#{step.sub("onboarding_", "")}"
        drop_nodes << drop_name
        drop_links << { source: step, target: drop_name, value: dropout }
      end

      all_nodes = (SANKEY_STEPS + drop_nodes).map { |s| { name: s } }
      all_links = forward_links + drop_links

      [ all_nodes, all_links ]
    end
  end
end
