require "csv"
require "set"

module RocketProgress
  # A current-data report of the bukux2 campaign, not a historical snapshot of
  # approval state. Late approvals and subsequent fraud deductions are included.
  class ContributorExport
    WINDOW = WINDOW_START...WINDOW_END.next_day.beginning_of_day
    HEADERS = %w[user_id username slack_id counted_ships approved_hours].freeze

    def rows
      @rows ||= begin
        totals = {}
        RocketProgress.approved_reviews
          .where(post_ship_events: { created_at: WINDOW })
          .pluck(:user_id, :post_ship_event_id, Arel.sql(RocketProgress::NET_MINUTES_SQL))
          .each do |user_id, ship_id, minutes|
            next unless minutes.positive?

            total = totals[user_id] ||= { minutes: 0, ships: Set.new }
            total[:minutes] += minutes
            total[:ships] << ship_id
          end

        User.where(id: totals.keys).order(:id).pluck(:id, :display_name, :slack_id).map do |id, name, slack_id|
          total = totals.fetch(id)
          [ id, safe_cell(name), safe_cell(slack_id), total[:ships].size, (total[:minutes] / 60.0).round(2) ]
        end
      end
    end

    def to_csv
      CSV.generate do |csv|
        csv << HEADERS
        rows.each { |row| csv << row }
      end
    end

    private

    def safe_cell(value)
      text = value.to_s
      # Quoting CSV alone does not prevent spreadsheet formula execution.
      text.match?(/\A(?:\s*[=+\-@]|[\t\r\n])/) ? "'#{text}" : text
    end
  end
end
