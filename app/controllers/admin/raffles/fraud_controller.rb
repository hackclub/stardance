module Admin
  module Raffles
    class FraudController < Admin::ApplicationController
      def show
        authorize :admin, :access_raffles?

        @flagged = build_flagged_list
        @total_referrals = @flagged.sum { |f| f[:total_referrals] }
        @total_referred_users = if @flagged.any?
          Raffle::Referral
            .where(participant_id: @flagged.map { |f| f[:participant].id })
            .where(ACTIVE_REFERRAL)
            .distinct.count(:referred_user_id)
        else
          0
        end
      end

      def reject_all_flagged
        authorize :admin, :access_raffles?

        flagged_pids = build_flagged_list.map { |f| f[:participant].id }
        rejected = 0

        ::PaperTrail.request(whodunnit: current_user.id) do
          Raffle::Referral.where(participant_id: flagged_pids)
                          .where.not(status: [ :self_referral, :rejected ])
                          .find_each do |referral|
            referral.paper_trail_event = "fraud_bulk_reject"
            referral.update!(status: :rejected, credited_week: nil)
            rejected += 1
          end
        end

        redirect_to admin_raffles_fraud_path, notice: "Rejected #{rejected} referrals across #{flagged_pids.size} participants."
      end

      def reject_and_ban_all_flagged
        authorize :admin, :access_raffles?

        flagged_pids = build_flagged_list.map { |f| f[:participant].id }
        rejected = 0
        banned = 0

        ::PaperTrail.request(whodunnit: current_user.id) do
          Raffle::Referral.where(participant_id: flagged_pids)
                          .where.not(status: [ :self_referral, :rejected ])
                          .includes(:referred_user)
                          .find_each do |referral|
            referral.paper_trail_event = "fraud_bulk_reject"
            referral.update!(status: :rejected, credited_week: nil)
            rejected += 1

            user = referral.referred_user
            next unless user && !user.banned?
            reason = "Raffle referral fraud (bulk)"
            user.ban!(reason: reason)
            ::PaperTrail::Version.create!(
              item_type: "User", item_id: user.id, event: "banned",
              whodunnit: current_user.id.to_s,
              object_changes: { banned: [ false, true ], banned_reason: [ nil, reason ] }.to_json
            )
            banned += 1
          end
        end

        redirect_to admin_raffles_fraud_path,
                    notice: "Rejected #{rejected} referrals, banned #{banned} users across #{flagged_pids.size} participants."
      end

      def cleared
        authorize :admin, :access_raffles?

        @cleared = Raffle::Participant
          .where(fraud_cleared: true)
          .includes(:user)
          .order(updated_at: :desc)
      end

      private

      ACTIVE_REFERRAL = "raffle_referrals.status NOT IN ('self_referral', 'rejected')"
      ELIGIBLE_PARTICIPANT = "p.eligible = true AND p.fraud_cleared = false"
      NOT_BANNED_REFERRER = "(referrer.banned = false OR referrer.id IS NULL)"

      BASE_JOINS = <<~SQL.squish
        INNER JOIN raffle_participants p ON p.id = raffle_referrals.participant_id
        LEFT JOIN users referrer ON referrer.id = p.user_id
        INNER JOIN users referred ON referred.id = raffle_referrals.referred_user_id
      SQL

      def build_flagged_list
        signals = Hash.new { |h, k| h[k] = { signals: [] } }

        add_referred_ip_signals(signals)
        add_referrer_ip_signals(signals)
        add_subnet_signals(signals)
        add_user_agent_signals(signals)
        add_timing_signals(signals)
        add_velocity_signals(signals)
        add_ghost_signals(signals)
        add_disposable_email_signals(signals)
        add_plus_addressing_signals(signals)

        return [] if signals.empty?

        participants = Raffle::Participant.includes(:user).where(id: signals.keys).index_by(&:id)
        referral_counts = Raffle::Referral
          .where(participant_id: signals.keys)
          .where(ACTIVE_REFERRAL)
          .group(:participant_id)
          .count

        signals.filter_map do |pid, data|
          participant = participants[pid]
          next unless participant

          {
            participant: participant,
            signals: data[:signals],
            total_referrals: referral_counts[pid] || 0
          }
        end.sort_by { |r| [ -r[:total_referrals], -r[:signals].sum { |s| s[:weight] } ] }
      end

      def add_referred_ip_signals(signals)
        rows = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins(BASE_JOINS)
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .where("referred.ip_address IS NOT NULL")
          .group("raffle_referrals.participant_id", "referred.ip_address")
          .having("COUNT(*) >= 3")
          .pluck(Arel.sql("raffle_referrals.participant_id"), Arel.sql("referred.ip_address"), Arel.sql("COUNT(*)"))

        rows.group_by(&:first).each do |pid, group|
          top_ip, top_count = group.max_by(&:last)&.slice(1, 2)
          total = group.sum(&:last)
          signals[pid][:signals] << {
            type: :shared_ip,
            label: "#{total} referred users share an IP",
            detail: "top: #{top_ip} (#{top_count})",
            weight: total
          }
        end
      end

      def add_referrer_ip_signals(signals)
        rows = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins(BASE_JOINS)
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .where("referrer.ip_address IS NOT NULL AND referrer.ip_address = referred.ip_address")
          .group("raffle_referrals.participant_id")
          .pluck(Arel.sql("raffle_referrals.participant_id"), Arel.sql("COUNT(*)"))

        rows.each do |pid, count|
          signals[pid][:signals] << {
            type: :self_ip,
            label: "#{count} referred from referrer's own IP",
            weight: count * 5
          }
        end
      end

      def add_subnet_signals(signals)
        rows = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins(BASE_JOINS)
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .where("referred.ip_address LIKE '%:%'")
          .group(
            "raffle_referrals.participant_id",
            Arel.sql("SPLIT_PART(referred.ip_address::text, ':', 1) || ':' || SPLIT_PART(referred.ip_address::text, ':', 2) || ':' || SPLIT_PART(referred.ip_address::text, ':', 3)")
          )
          .having("COUNT(*) >= 5")
          .having("COUNT(DISTINCT referred.ip_address) >= 2")
          .pluck(
            Arel.sql("raffle_referrals.participant_id"),
            Arel.sql("SPLIT_PART(referred.ip_address::text, ':', 1) || ':' || SPLIT_PART(referred.ip_address::text, ':', 2) || ':' || SPLIT_PART(referred.ip_address::text, ':', 3)"),
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(DISTINCT referred.ip_address)")
          )

        rows.group_by(&:first).each do |pid, group|
          top = group.max_by { |r| r[2] }
          signals[pid][:signals] << {
            type: :subnet,
            label: "#{top[2]} referred from same /48 subnet",
            detail: "#{top[1]}::/48, #{top[3]} distinct IPs",
            weight: top[2]
          }
        end
      end

      def add_user_agent_signals(signals)
        rows = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins(BASE_JOINS)
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .where("referred.user_agent IS NOT NULL")
          .group("raffle_referrals.participant_id", "referred.user_agent")
          .having("COUNT(*) >= 10")
          .pluck(Arel.sql("raffle_referrals.participant_id"), Arel.sql("COUNT(*)"))

        rows.group_by(&:first).each do |pid, group|
          top_count = group.max_by(&:last)&.last
          signals[pid][:signals] << {
            type: :user_agent,
            label: "#{top_count} referred share exact browser",
            weight: top_count
          }
        end
      end

      def add_timing_signals(signals)
        by_participant = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins("INNER JOIN raffle_participants p ON p.id = raffle_referrals.participant_id")
          .joins("LEFT JOIN users referrer ON referrer.id = p.user_id")
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .order(:participant_id, :created_at)
          .pluck(:participant_id, :created_at)
          .group_by(&:first)

        by_participant.each do |pid, rows|
          next if rows.size < 4
          gaps = rows.map(&:last).sort.each_cons(2).map { |a, b| (b - a).to_f }
          next if gaps.empty?

          median = gaps.sort[gaps.size / 2]
          next if median > 120

          mean = gaps.sum / gaps.size
          next if mean.zero?
          stddev = Math.sqrt(gaps.sum { |g| (g - mean)**2 } / gaps.size)
          cv = stddev / mean
          next if cv > 0.5

          signals[pid][:signals] << {
            type: :timing,
            label: "#{median.round}s median gap, CV #{cv.round(2)}",
            weight: rows.size * 3
          }
        end
      end

      def add_velocity_signals(signals)
        by_participant = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins("INNER JOIN raffle_participants p ON p.id = raffle_referrals.participant_id")
          .joins("LEFT JOIN users referrer ON referrer.id = p.user_id")
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .where("raffle_referrals.created_at > ?", 30.days.ago)
          .order(:participant_id, :created_at)
          .pluck(:participant_id, :created_at)
          .group_by(&:first)

        by_participant.each do |pid, rows|
          next if rows.size < 5
          timestamps = rows.map(&:last).sort
          burst = detect_burst(timestamps, window: 24.hours, threshold: 5)
          next unless burst

          signals[pid][:signals] << {
            type: :velocity,
            label: "#{burst[:count]} referrals in 24h",
            detail: "started #{burst[:at].strftime('%Y-%m-%d %H:%M')}",
            weight: burst[:count]
          }
        end
      end

      def add_ghost_signals(signals)
        rows = Raffle::Referral
          .status_verified
          .joins(BASE_JOINS)
          .joins("LEFT JOIN project_memberships pm ON pm.user_id = referred.id")
          .joins("LEFT JOIN user_hackatime_projects hp ON hp.user_id = referred.id")
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .group("raffle_referrals.participant_id")
          .pluck(
            Arel.sql("raffle_referrals.participant_id"),
            Arel.sql("COUNT(DISTINCT raffle_referrals.id)"),
            Arel.sql("COUNT(DISTINCT raffle_referrals.id) FILTER (WHERE pm.id IS NULL AND hp.id IS NULL)")
          )

        rows.each do |pid, total, ghost|
          next if ghost < 3 || ghost * 2 < total
          signals[pid][:signals] << {
            type: :ghost,
            label: "#{ghost}/#{total} verified referrals are ghost accounts",
            weight: 1
          }
        end
      end

      DISPOSABLE_DOMAINS = %w[
        wwwalpha.net minitts.net ozsaip.com yzcalo.com ruutukf.com
        slurpinbox.com aspensif.com wshu.net zazamail.link temprelay.net
        web-library.net 5nek.com fanchatu.com herojp.com dosbee.com
        bncinema.com brixozu.com fixscal.com lnovic.com gmeenramy.com
        bwmyga.com bltiwd.com wnbaldwy.com guerrillamailblock.com aleeas.com
        guerrillamail.com mailinator.com tempmail.com throwaway.email
        yopmail.com trashmail.com sharklasers.com guerrillamail.info
        grr.la dispostable.com maildrop.cc mailnesia.com tempail.com
      ].freeze

      def add_disposable_email_signals(signals)
        rows = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins(BASE_JOINS)
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .where("LOWER(SPLIT_PART(referred.email, '@', 2)) IN (?)", DISPOSABLE_DOMAINS)
          .group("raffle_referrals.participant_id")
          .pluck(Arel.sql("raffle_referrals.participant_id"), Arel.sql("COUNT(*)"))

        rows.each do |pid, count|
          signals[pid][:signals] << {
            type: :disposable_email,
            label: "#{count} referred use disposable email",
            weight: count * 5
          }
        end
      end

      def add_plus_addressing_signals(signals)
        rows = Raffle::Referral
          .where(ACTIVE_REFERRAL)
          .joins(BASE_JOINS)
          .where(ELIGIBLE_PARTICIPANT).where(NOT_BANNED_REFERRER)
          .where("referred.email LIKE '%+%@gmail.com'")
          .group("raffle_referrals.participant_id")
          .having("COUNT(*) >= 2")
          .pluck(Arel.sql("raffle_referrals.participant_id"), Arel.sql("COUNT(*)"))

        rows.each do |pid, count|
          signals[pid][:signals] << {
            type: :plus_addressing,
            label: "#{count} referred use gmail +aliases",
            weight: count * 5
          }
        end
      end

      def detect_burst(timestamps, window:, threshold:)
        j = 0
        timestamps.each_with_index do |ts, i|
          j = [ j, i ].max
          j += 1 while j < timestamps.size && timestamps[j] <= ts + window
          count = j - i
          return { at: ts, count: count } if count >= threshold
        end
        nil
      end
    end
  end
end
