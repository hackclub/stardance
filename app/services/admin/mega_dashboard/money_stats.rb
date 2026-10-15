module Admin
  module MegaDashboard
    # Stardust in and out of the ledger, alongside the program's HCB balance
    # and spend.
    #
    # The old dashboard derived cost per hour by hand from a weighted-total
    # field and by paging every HCB transaction. The YSWS Programs row carries
    # Cost/Hour, Budget/Hour, Total Spend and Over Budget directly now, so
    # those are read rather than recomputed, and they agree with what the YSWS
    # team reports.
    class MoneyStats
      HCB_ORG = "stardance".freeze
      HCB_BASE = "https://hcb.hackclub.com/api/v3".freeze
      # A balance under this reads as urgent on the panel.
      LOW_BALANCE_CENTS = 200_000

      def initialize(now: Time.current)
        @now = now
      end

      def to_h
        {
          ledger: ledger,
          hcb: hcb,
          program: program
        }
      end

      private

      def ledger
        recent = ::LedgerEntry.where(created_at: 24.hours.ago..)
        granted, spent, transactions = recent.pick(
          Arel.sql("COALESCE(SUM(amount) FILTER (WHERE amount > 0), 0)"),
          Arel.sql("COALESCE(SUM(ABS(amount)) FILTER (WHERE amount < 0), 0)"),
          Arel.sql("COUNT(*)")
        )

        total_granted = ::LedgerEntry.where("amount > 0").sum(:amount)
        total_spent = ::LedgerEntry.where("amount < 0").sum(:amount).abs

        {
          outstanding: total_granted - total_spent,
          total_granted: total_granted,
          total_spent: total_spent,
          utilization: total_granted.zero? ? nil : ((total_spent / total_granted.to_f) * 100).round(1),
          granted_24h: granted,
          spent_24h: spent,
          transactions_24h: transactions
        }
      end

      def hcb
        Rails.cache.fetch("mega_dashboard_hcb", expires_in: 1.hour) do
          response = Faraday.get("#{HCB_BASE}/organizations/#{HCB_ORG}") do |req|
            req.options.timeout = 10
            req.options.open_timeout = 5
          end
          raise "HCB returned #{response.status}" unless response.success?

          balances = JSON.parse(response.body).fetch("balances", {})
          balance = balances["balance_cents"].to_i
          raised = balances["total_raised"].to_i

          { balance_cents: balance, total_raised_cents: raised, spent_cents: raised - balance, low: balance < LOW_BALANCE_CENTS }
        end
      rescue StandardError => e
        { error: e.message.presence || "HCB is temporarily unavailable" }
      end

      # Airtable lookup and rollup fields come back as arrays even when they
      # hold a single value, so every field is unwrapped before it reaches the
      # view rather than trusting the column type.
      def scalar(value) = value.is_a?(Array) ? value.first : value

      def number(value) = scalar(value).to_f.round

      def program
        return { error: "No Airtable key configured" } unless NpsStats.configured?

        Rails.cache.fetch("mega_dashboard_program", expires_in: 1.hour) do
          fields = Norairrecord.table(NpsStats.api_key, NpsStats::BASE_ID, NpsStats::PROGRAMS_TABLE)
                               .find(NpsStats::PROGRAM_RECORD_ID)
                               .fields

          {
            cost_per_hour: scalar(fields["Cost/Hour"]),
            budget_per_hour: scalar(fields["Budget/Hour"]),
            over_budget: scalar(fields["Over Budget"]),
            total_spend: scalar(fields["Total Spend"]),
            total_sign_ups: number(fields["Total Sign Ups"]),
            unique_shippers: number(fields["Unique Shippers"]),
            grants_awarded: number(fields["Grants Awarded"]),
            weighted_total: scalar(fields["Weighted–Total"])
          }
        end
      rescue StandardError => e
        { error: e.message.presence || "Program stats are temporarily unavailable" }
      end
    end
  end
end
