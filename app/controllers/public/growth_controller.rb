module Public
  # Duolingo-style growth model: daily user states, the rates users move
  # between them, and which rate is worth improving. Snapshots are built
  # nightly by GrowthRefreshJob; this page only reads them.
  class GrowthController < ApplicationController
    REBUILD_DAYS = 30

    def show
      authorize :growth

      metric = params[:metric].presence_in(GrowthDailySnapshot::METRICS.keys) || GrowthDailySnapshot::SOURCE_OF_TRUTH
      signups = params[:signups].presence_in(Growth::Simulator::SIGNUPS) || "word_of_mouth"
      @report = Growth::Report.new(metric:, signups:)
    end

    def rebuild
      authorize :growth

      GrowthRefreshJob.perform_later(days: REBUILD_DAYS)
      ::PaperTrail::Version.create!(
        item_type: "User", item_id: current_user.id, event: "rebuild_growth_model",
        whodunnit: current_user.id.to_s,
        object_changes: { rebuilt_days: [ nil, REBUILD_DAYS ] }
      )
      redirect_to public_growth_path(metric: params[:metric]), notice: "Rebuilding the last #{REBUILD_DAYS} days. Refresh in a few minutes."
    end
  end
end
