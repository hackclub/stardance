module Admin
  class LedgerEntriesController < Admin::ApplicationController
    SORT_COLUMNS = {
      "created_at" => "ledger_entries.created_at",
      "amount" => "ledger_entries.amount",
      "user" => "users.display_name",
      "source" => "ledger_entries.ledgerable_type"
    }.freeze

    def index
      authorize LedgerEntry

      set_filter_values
      filtered_entries = apply_filters(LedgerEntry.joins(:user))

      set_summaries(filtered_entries)
      set_chart_data(filtered_entries)

      @sort = SORT_COLUMNS.key?(params[:sort]) ? params[:sort] : "created_at"
      @direction = params[:direction] == "asc" ? "asc" : "desc"
      ordered_entries = filtered_entries.order(Arel.sql("#{SORT_COLUMNS.fetch(@sort)} #{@direction}"), id: @direction)
      @pagy, @ledger_entries = pagy(:offset, ordered_entries.includes(:user), limit: 50)
    end

    private

    def set_filter_values
      @start_date = parse_date(params[:start_date]) || 29.days.ago.to_date
      @end_date = parse_date(params[:end_date]) || Time.zone.today
      @start_date, @end_date = @end_date, @start_date if @start_date > @end_date
      @selected_categories = Array(params[:categories]).select { |key| LedgerEntry::CATEGORIES.key?(key) }
      @direction_filter = %w[credit debit].include?(params[:entry_direction]) ? params[:entry_direction] : nil
      @user_query = params[:user_query].to_s.strip
      @search_query = params[:search].to_s.strip
    end

    def apply_filters(scope)
      scope = scope.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
      scope = filter_categories(scope)
      scope = scope.where("ledger_entries.amount > 0") if @direction_filter == "credit"
      scope = scope.where("ledger_entries.amount < 0") if @direction_filter == "debit"
      scope = filter_users(scope) if @user_query.present?
      scope = filter_text(scope) if @search_query.present?
      scope
    end

    def filter_categories(scope)
      return scope if @selected_categories.empty?

      known_types = LedgerEntry::CATEGORIES.except("other").values.flat_map { |details| details[:types] }
      selected_types = @selected_categories.flat_map { |key| LedgerEntry::CATEGORIES.fetch(key)[:types] }
      conditions = []
      conditions << LedgerEntry.arel_table[:ledgerable_type].in(selected_types) if selected_types.any?
      conditions << LedgerEntry.arel_table[:ledgerable_type].not_in(known_types) if @selected_categories.include?("other")
      scope.where(conditions.reduce(&:or))
    end

    def filter_users(scope)
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@user_query)}%"
      condition = User.arel_table[:display_name].matches(pattern)
        .or(User.arel_table[:email].matches(pattern))
      condition = condition.or(User.arel_table[:id].eq(@user_query.to_i)) if @user_query.match?(/\A\d+\z/)
      scope.where(condition)
    end

    def filter_text(scope)
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@search_query)}%"
      condition = LedgerEntry.arel_table[:reason].matches(pattern)
        .or(LedgerEntry.arel_table[:created_by].matches(pattern))
      condition = condition.or(LedgerEntry.arel_table[:ledgerable_id].eq(@search_query.to_i)) if @search_query.match?(/\A\d+\z/)
      scope.where(condition)
    end

    def set_summaries(scope)
      @entry_count = scope.count
      @stardust_issued = scope.where("ledger_entries.amount > 0").sum(:amount)
      @stardust_spent = scope.where("ledger_entries.amount < 0").sum(:amount).abs
      @net_movement = @stardust_issued - @stardust_spent
    end

    def set_chart_data(scope)
      daily_totals = scope.group("DATE(ledger_entries.created_at)").pluck(
        Arel.sql("DATE(ledger_entries.created_at)"),
        Arel.sql("COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0)"),
        Arel.sql("COALESCE(ABS(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END)), 0)")
      ).to_h { |date, issued, spent| [ date, { issued: issued, spent: spent } ] }

      @flow_chart_data = (@start_date..@end_date).map do |date|
        totals = daily_totals.fetch(date, { issued: 0, spent: 0 })
        { date: date.iso8601, issued: totals[:issued], spent: totals[:spent], net: totals[:issued] - totals[:spent] }
      end

      grouped = Hash.new { |hash, key| hash[key] = { issued: 0, spent: 0 } }
      scope.group(:ledgerable_type).pluck(
        :ledgerable_type,
        Arel.sql("COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0)"),
        Arel.sql("COALESCE(ABS(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END)), 0)")
      ).each do |type, issued, spent|
        totals = grouped[LedgerEntry.category_key_for(type)]
        totals[:issued] += issued
        totals[:spent] += spent
      end

      @breakdown_chart_data = LedgerEntry::CATEGORIES.filter_map do |key, details|
        totals = grouped[key]
        next if totals[:issued].zero? && totals[:spent].zero?

        { label: details[:label], issued: totals[:issued], spent: totals[:spent] }
      end
    end

    def parse_date(value)
      Date.iso8601(value) if value.present?
    rescue Date::Error
      nil
    end
  end
end
