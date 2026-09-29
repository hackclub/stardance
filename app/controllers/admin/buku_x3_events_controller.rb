class Admin::BukuX3EventsController < Admin::ApplicationController
  def show
    authorize :admin, :index?
    @buku_discoveries = BukuX3::Assignment.discovered_counts
    @buku_event = BukuX3::Event.current || BukuX3::Event.new
    @buku_daily_shippers = @buku_event.daily_active_shippers.reverse
  end

  def update
    authorize :admin, :manage_buku_event?
    intensity = params.require(:buku_x3_event).require(:visual_intensity)
    event = BukuX3::Event.transaction do
      record = BukuX3::Event.create_or_find_by!(key: BukuX3::Event::KEY)
      record.update!(visual_intensity: intensity)
      record
    end
    redirect_to admin_jim_takeover_path, notice: "visual intensity set to #{event.visual_intensity}% · live pages update within a minute", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_jim_takeover_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def export_bukux2
    authorize :admin, :manage_buku_event?
    export = RocketProgress::ContributorExport.new
    csv = export.to_csv
    PaperTrail::Version.create!(
      item_type: "User", item_id: current_user.id, event: "export_bukux2_contributors",
      whodunnit: current_user.id.to_s,
      object_changes: {
        report: [ nil, "bukux2 contributors" ],
        ship_window_start: [ nil, RocketProgress::ContributorExport::WINDOW.begin.iso8601 ],
        ship_window_end_exclusive: [ nil, RocketProgress::ContributorExport::WINDOW.end.iso8601 ],
        exported_users: [ nil, export.rows.size ]
      }
    )
    response.headers["Cache-Control"] = "no-store"
    send_data csv, filename: "bukux2-contributors-through-2026-09-24.csv", type: "text/csv; charset=utf-8", disposition: "attachment"
  end
end
