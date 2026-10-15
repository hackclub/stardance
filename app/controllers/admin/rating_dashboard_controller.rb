class Admin::RatingDashboardController < Admin::ApplicationController
  SORT_FIELDS = %w[project owner status votes started hangtime paid].freeze

  def show
    authorize :rating_dashboard

    @snapshot = RatingDashboard::Snapshot.new(period: params[:period])
    @counts = @snapshot.counts
    @metrics = @snapshot.metrics
    @blocker_counts = @snapshot.blocker_counts
    @oldest_waiting = @snapshot.oldest_waiting
    @chart_data = @snapshot.chart_data.to_json
    @period = @snapshot.period
    @status = RatingDashboard::Snapshot::STATUSES.include?(params[:status]) ? params[:status] : nil
    @quality = %w[exact estimated unknown].include?(params[:quality]) ? params[:quality] : nil
    @query = params[:query].to_s.strip
    @sort = SORT_FIELDS.include?(params[:sort]) ? params[:sort] : "started"
    @direction = params[:direction] == "asc" ? "asc" : "desc"

    rows = filter_rows(@snapshot.rows)
    rows = sort_rows(rows)
    @pagy, @rows = pagy(:offset, rows, limit: 25)
  end

  private

  def filter_rows(rows)
    rows = rows.select { |row| row.status == @status } if @status
    rows = rows.select { |row| quality_matches?(row) } if @quality
    return rows if @query.blank?

    query = @query.downcase
    rows.select do |row|
      row.project&.title&.downcase&.include?(query) ||
        row.owner&.display_name&.downcase&.include?(query) ||
        row.ship_event.id.to_s == query
    end
  end

  def quality_matches?(row)
    case @quality
    when "exact" then row.ship_event.lifecycle_data_quality.in?(%w[live backfilled_exact])
    when "estimated" then row.ship_event.lifecycle_data_quality == "backfilled_estimated"
    when "unknown" then row.ship_event.lifecycle_data_quality.blank?
    end
  end

  def sort_rows(rows)
    populated, empty = rows.partition { |row| sort_value(row).present? }
    populated.sort_by! { |row| sort_value(row) }
    populated.reverse! if @direction == "desc"
    populated + empty
  end

  def sort_value(row)
    case @sort
    when "project" then row.project&.title&.downcase
    when "owner" then row.owner&.display_name&.downcase
    when "status" then row.status
    when "votes" then row.votes_count
    when "started" then row.voting_started_at
    when "hangtime" then row.rating_hangtime
    when "paid" then row.paid_at
    end
  end
end
