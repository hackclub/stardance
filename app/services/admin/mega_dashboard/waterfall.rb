module Admin
  module MegaDashboard
    # End-to-end time from ship submission to payout, broken into the stages a
    # ship actually sits in, read like a browser network waterfall: each stage
    # splits into the time it waited unclaimed and the time a reviewer held it.
    #
    # Only ships that reached payout inside the window are measured, so the
    # bars describe journeys that actually finished rather than a mix of
    # finished and in-flight work.
    class Waterfall
      PERIODS = QueueStats::PERIODS

      # Ships take different routes to payout, and averaging them together
      # produces a number that describes nobody. Each path is measured on its own.
      # Hardware is two separate journeys with a build in between, not one
      # continuous wait: a user waits for funding, buys parts and builds
      # (their own time, not a queue), then waits for build certification and
      # payout. Measuring it end to end would report the build as review time.
      PATHS = {
        "voting" => "Standard (voting)",
        "static_prize" => "Fixed-prize mission",
        "hardware_design" => "Hardware design (funding)",
        "hardware_build" => "Hardware build"
      }.freeze

      # YSWS review is deliberately absent: it is internal grant processing the
      # user never waits on, so counting it would overstate what they actually
      # experience. Its return_at is still read, but only to flag rework.
      STAGES = [
        { key: "funding_wait", label: "Waiting for a reviewer" },
        { key: "ship_cert", label: "Ship certification" },
        { key: "voting", label: "Rating" },
        { key: "payout", label: "Payout" }
      ].freeze

      # A fixed-prize ship never enters voting, so the span between its cert
      # decision and its payout is the mission reviewer deciding, not a payout
      # queue. Same measurement, honest label.
      STAGE_LABELS_BY_PATH = {
        "static_prize" => { "payout" => "Mission review" },
        "hardware_build" => { "ship_cert" => "Build certification" }
      }.freeze

      Journey = Data.define(:ship_event_id, :path, :segments, :reworked)

      def initialize(period: QueueStats::DEFAULT_PERIOD, now: Time.current)
        @period = PERIODS.key?(period.to_s) ? period.to_s : QueueStats::DEFAULT_PERIOD
        @now = now
        @journeys = build_journeys + build_funding_journeys
      end

      def to_h
        {
          period: @period,
          paths: PATHS.keys.index_with { |path| summarise(@journeys.select { |j| j.path == path }, path: path) },
          overall: summarise(@journeys),
          excluded: excluded_counts
        }
      end

      private

      def window_start = (@now - (PERIODS.fetch(@period) - 1).days).beginning_of_day

      # A fixed-prize mission never pays stardust, so it never gets a paid_at:
      # its journey ends when the mission reviewer approves the prize. Keying
      # the whole waterfall off paid_at made that path permanently empty.
      def finished_at_for(path, paid_at, submission_reviewed_at)
        return submission_reviewed_at || paid_at if path == "static_prize"

        paid_at
      end

      # Only the voting path reads the backfilled voting timestamps, so only it
      # needs the data-quality gate. Applying it everywhere threw away the
      # fixed-prize and hardware journeys, whose stages come from the ship cert
      # and the mission review instead.
      def measurable?(path, quality)
        return true unless path == "voting"

        %w[live backfilled_exact].include?(quality)
      end

      def build_journeys
        ships = ::Post::ShipEvent
          .left_outer_joins(:mission_submission, post: :project)
          .where(
            "post_ship_events.paid_at >= :since OR (mission_submissions.payout_path = 'static_prize' AND mission_submissions.reviewed_at >= :since)",
            since: window_start
          )
          .pluck(
            Arel.sql("post_ship_events.id"),
            Arel.sql("post_ship_events.created_at"),
            Arel.sql("post_ship_events.voting_started_at"),
            Arel.sql("post_ship_events.voting_completed_at"),
            Arel.sql("post_ship_events.paid_at"),
            Arel.sql("post_ship_events.lifecycle_data_quality"),
            Arel.sql("projects.hardware_stage"),
            Arel.sql("mission_submissions.payout_path"),
            Arel.sql("mission_submissions.reviewed_at")
          )

        ids = ships.map(&:first)
        ship_certs = ::Certification::Ship
          .where(post_ship_event_id: ids)
          .pluck(:post_ship_event_id, :created_at, :claimed_at, :decided_at, :recert_reason)
          .index_by(&:first)
        returned_ysws = ::Certification::Ysws
          .where(post_ship_event_id: ids).where.not(returned_at: nil)
          .pluck(:post_ship_event_id).to_set

        @excluded = 0

        ships.filter_map do |id, shipped_at, voting_started_at, voting_completed_at, paid_at,
                             quality, hardware_stage, payout_path, submission_reviewed_at|
          path = path_for(hardware_stage, payout_path)
          finished_at = finished_at_for(path, paid_at, submission_reviewed_at)
          next unless finished_at && finished_at >= window_start

          unless measurable?(path, quality)
            @excluded += 1
            next
          end

          cert = ship_certs[id]
          segments = {}
          segments["ship_cert"] = split(cert&.[](1) || shipped_at, cert&.[](2), cert&.[](3))
          segments["voting"] = split(voting_started_at, nil, voting_completed_at) if voting_started_at
          segments["payout"] = split(voting_completed_at || cert&.[](3), nil, finished_at)

          total = finished_at && shipped_at ? finished_at - shipped_at : nil
          next unless total&.positive?

          Journey.new(
            ship_event_id: id,
            path: path,
            segments: segments.compact,
            reworked: returned_ysws.include?(id) || cert&.[](4).present?
          )
        end
      end

      # A funding request is its own short journey: the stretch it sits waiting
      # for a reviewer. It happens before the build, so it is measured
      # separately rather than folded into the build's timeline.
      def build_funding_journeys
        ::Certification::FundingRequest
          .where(decided_at: window_start..)
          .pluck(:id, :created_at, :claimed_at, :decided_at)
          .filter_map do |id, created_at, claimed_at, decided_at|
            total = decided_at - created_at
            next unless total.positive?

            claimed_at = decided_at unless claimed_at&.between?(created_at, decided_at)

            Journey.new(
              ship_event_id: id,
              path: "hardware_design",
              segments: { "funding_wait" => { wait: claimed_at - created_at, work: 0.0 } },
              reworked: false
            )
          end
      end

      def path_for(hardware_stage, payout_path)
        return "hardware_build" if hardware_stage.present?
        return "static_prize" if payout_path == "static_prize"

        "voting"
      end

      # A stage is `wait` (sitting unclaimed) then `work` (a reviewer holding
      # it). Stages with no claim concept report the whole span as wait.
      def split(entered_at, claimed_at, left_at)
        return if entered_at.nil? || left_at.nil? || left_at < entered_at

        if claimed_at && claimed_at.between?(entered_at, left_at)
          { wait: claimed_at - entered_at, work: left_at - claimed_at }
        else
          { wait: left_at - entered_at, work: 0.0 }
        end
      end

      # Each segment is the MEDIAN time a ship spends in that step. Medians are
      # not additive, so the segments deliberately do not add up to an
      # end-to-end figure and none is shown: a step's median is the honest
      # answer to "how long does this usually take", and a journey total built
      # from them would be a number no ship ever experienced.
      def summarise(journeys, path: nil)
        return { count: 0, stages: [], rework_rate: nil } if journeys.empty?

        labels = STAGE_LABELS_BY_PATH.fetch(path, {})
        rows = journeys.map { |journey| durations_for(journey) }

        medians = STAGES.filter_map do |stage|
          # Only journeys that actually pass through the step count toward its
          # median; a path that skips a stage would otherwise drag it to zero.
          values = rows.filter_map { |row| row[stage[:key]] }
          median = median_of(values)
          [ stage, values.size, median ] if median
        end

        # Widths are each step's share of the summed medians, so the bar stays
        # full and the steps stay visually comparable. Shares come off the raw
        # seconds, so a step short enough to round to 0.0h still draws.
        total = medians.sum { |_stage, _count, median| median }
        stages = medians.map do |stage, count, median|
          {
            key: stage[:key],
            label: labels.fetch(stage[:key], stage[:label]),
            count: count,
            median_hours: (median / 3600.0).round(1),
            share: total.positive? ? ((median / total) * 100).round(1) : nil
          }
        end

        {
          count: journeys.size,
          stages: stages,
          rework_rate: ((journeys.count(&:reworked) * 100.0) / journeys.size).round(1)
        }
      end

      def median_of(values)
        return if values.empty?

        values.sort[(values.size - 1) / 2]
      end

      # Stages the journey skipped stay nil so they don't count as zero.
      def durations_for(journey)
        STAGES.to_h { |stage| [ stage[:key], segment_total(journey, stage[:key]) ] }
      end

      def segment_total(journey, key)
        segment = journey.segments[key]
        segment && segment[:wait] + segment[:work]
      end

      # Voting journeys dropped for unusable backfill timestamps.
      def excluded_counts = { estimated_or_unknown: @excluded.to_i }
    end
  end
end
