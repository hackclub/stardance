module Admin
  # Where every devlogged hour went: deleted, never shipped, or shipped and
  # then through ship certification, the YSWS review, the integrity check
  # and the Airtable sync. Built as Sankey nodes and links in two units, hours
  # and ships, so the same graph reads as "how much time" or "how many ships".
  #
  # All time, software and hardware. Hardware skips the integrity check, so
  # its ships pass through their own kept node on the way to Airtable, and a
  # ship a reviewer misfiled into the wrong queue has its own held state.
  #
  # Deleted work is not dropped at the top. Each deleted devlog carries the
  # moment it went (its own deleted_at, or the project's when the project was
  # deleted or its owner banned) and flows through every stage whose own
  # timestamp is earlier, then leaks out there. So "banned after shipping"
  # fed from the Airtable node means hours that were synced and then banned.
  #
  # Every ship is in exactly one state at a time, so the ship unit only flows
  # through nodes that take a whole ship out of the funnel. A markdown, a
  # deduction or a single deleted devlog removes hours but the ship carries
  # on, so those nodes carry a ships_affected count instead of a ship flow.
  class HourFunnel
    Node = Data.define(:key, :label, :stage, :kind, :partial)

    # Order matters twice: it is the vertical order inside a Sankey column,
    # and the kept node of each stage comes first so the main flow stays on
    # top. kind is what the chart colours: kept (flows on), held (waiting on
    # someone), lost (never comes back).
    NODES = [
      Node.new("devlogged", "Devlogged", "devlogged", "kept", false),
      Node.new("shipped", "Shipped", "shipped", "kept", false),
      Node.new("unshipped", "Not shipped yet", "shipped", "held", false),
      Node.new("deleted", "Devlog deleted before shipping", "shipped", "lost", false),
      Node.new("project_gone", "Project deleted or banned before shipping", "shipped", "lost", false),
      Node.new("ship_approved", "Ship approved", "ship_cert", "kept", false),
      Node.new("ship_approved_after_return", "Ship approved after a return", "ship_cert", "kept", false),
      Node.new("ship_pending", "Ship cert pending", "ship_cert", "held", false),
      Node.new("ship_resubmitted", "Resubmitted, pending again", "ship_cert", "held", false),
      Node.new("ship_returned", "Returned, waiting on builder", "ship_cert", "held", false),
      Node.new("ship_misfiled", "Misfiled, builder answering", "ship_cert", "held", false),
      Node.new("ship_withdrawn", "Withdrawn", "ship_cert", "held", false),
      Node.new("ship_rejected", "Ship rejected", "ship_cert", "lost", false),
      Node.new("ysws_approved", "YSWS approved", "ysws", "kept", false),
      Node.new("ysws_pending", "YSWS review pending", "ysws", "held", false),
      Node.new("ysws_marked_down", "Marked down by YSWS", "ysws", "lost", true),
      Node.new("ysws_rejected", "Devlogs rejected by YSWS", "ysws", "lost", true),
      Node.new("ysws_under_minimum", "Review rejected (under 6 min)", "ysws", "lost", false),
      Node.new("integrity_passed", "Integrity passed", "integrity", "kept", false),
      Node.new("integrity_skipped", "No integrity check (hardware)", "integrity", "kept", false),
      Node.new("integrity_pending", "Integrity pending", "integrity", "held", false),
      Node.new("integrity_deducted", "Deducted by integrity", "integrity", "lost", true),
      Node.new("integrity_banned", "Banned by integrity", "integrity", "lost", false),
      Node.new("airtable_synced", "In Airtable", "airtable", "kept", false),
      Node.new("airtable_unsynced", "Awaiting Airtable sync", "airtable", "held", false),
      Node.new("payout_basis", "Within 10h/devlog payout cap", "payout_cap", "kept", false),
      Node.new("over_payout_cap", "Over 10h/devlog payout cap", "payout_cap", "lost", true),
      Node.new("gone_banned", "Banned after shipping", "gone", "lost", false),
      Node.new("gone_project_deleted", "Project deleted after shipping", "gone", "lost", false),
      Node.new("gone_devlog_deleted", "Devlog deleted after shipping", "gone", "lost", true)
    ].freeze

    NODES_BY_KEY = NODES.index_by(&:key).freeze

    GONE_NODES = {
      "banned" => "gone_banned",
      "project_deleted" => "gone_project_deleted",
      "devlog_deleted" => "gone_devlog_deleted"
    }.freeze

    PAYOUT_CAP_HOURS = ::Post::ShipEvent::MAX_PAYOUT_HOURS_PER_DEVLOG

    AUTO_REJECT_JUSTIFICATIONS = ::Certification::YswsReviewRejector::JUSTIFICATIONS.values.freeze

    SHIP_STATUSES = ::Certification::Ship.statuses.invert.freeze
    INTEGRITY_STATUSES = ::Certification::Integrity.statuses.invert.freeze
    INTEGRITY_PASSED = %w[auto_passed manually_passed].freeze

    # One segment of a ship's hours: its live devlogs, or the devlogs that
    # went at one moment and had reached one stage by then. A live ship has
    # one live segment plus one per distinct deletion; a deleted project's
    # ship has exactly one.
    ShipRow = Struct.new(
      :ship_event_id, :hardware, :gone, :reached, :certification_status, :review_status, :recert_from_ysws, :bounced,
      :ysws_reviewed, :ysws_returned, :approved_minutes_all, :airtable_synced, :in_unified_db,
      :integrity_status, :deduction_minutes,
      :hours, :devlogs, :raw_over_cap_hours, :over_cap_devlogs, :rejected_hours, :auto_rejected_hours,
      :approved_hours, :marked_down_hours, :unreviewed_hours, :certified_over_cap_hours,
      keyword_init: true
    ) do
      # A single deleted devlog leaves its ship behind; a deleted project or
      # a ban takes the ship with it.
      def whole_ship? = gone != "devlog_deleted"

      def gone_node = GONE_NODES[gone]
    end

    def to_h
      @hours = Hash.new(0.0)
      @ships = Hash.new(0)
      @ships_affected = Hash.new { |h, k| h[k] = Set.new }
      @links = Hash.new { |h, k| h[k] = { hours: 0.0, ships: 0 } }
      @details = Hash.new(0)

      add_devlog_stage
      ship_rows.each { |row| add_ship(row) }

      {
        unit_labels: { hours: "hours", ships: "ships" },
        nodes: NODES.map { |node| node_payload(node) },
        links: @links.map { |(source, target), value| { source: source, target: target, hours: round(value[:hours]), ships: value[:ships] } },
        details: @details.transform_values { |value| value.is_a?(Float) ? round(value) : value }
      }
    end

    private

    def node_payload(node)
      {
        key: node.key, label: node.label, stage: node.stage, kind: node.kind, partial: node.partial,
        hours: round(@hours[node.key]),
        ships: node.partial ? nil : @ships[node.key],
        ships_affected: node.partial ? @ships_affected[node.key].size : nil
      }
    end

    def round(value) = value.to_f.round(1)

    # ---- stage A/B: every devlog, deleted or not ---------------------------

    def add_devlog_stage
      row = ::ActiveRecord::Base.connection.select_one(devlog_stage_sql)

      @hours["devlogged"] = row["gross"].to_f
      flow("devlogged", "deleted", hours: row["devlog_deleted_before_ship"].to_f)
      flow("devlogged", "project_gone", hours: row["banned_before_ship"].to_f + row["project_deleted_before_ship"].to_f)
      flow("devlogged", "unshipped", hours: row["unshipped_never"].to_f + row["unshipped_after_ship"].to_f)
      flow("devlogged", "shipped", hours: row["shipped"].to_f)

      %w[banned_before_ship project_deleted_before_ship unshipped_never unshipped_after_ship hardware design_phase].each do |key|
        @details["#{key}_hours"] = row[key].to_f
      end
      @details["devlogs"] = row["devlogs"].to_i
    end

    # ---- stages C..F: one ship segment at a time ----------------------------

    def add_ship(row)
      ships = row.whole_ship? ? 1 : 0
      @ships["shipped"] += ships
      record_payout_cap(row) if row.gone.nil?

      if row.gone && row.reached == "shipped"
        leak(row, "shipped", row.hours, ships)
        return
      end

      ship_node = ship_cert_node(row)
      flow("shipped", ship_node, hours: row.hours, ships: ships)
      if row.gone.nil? && row.recert_from_ysws
        @details["recert_from_ysws_hours"] += row.hours
        @details["recert_from_ysws_ships"] += 1
      end
      return unless ship_node.start_with?("ship_approved")

      if row.gone && row.reached == "ship_approved"
        leak(row, ship_node, row.hours, ships)
        return
      end

      approved = add_ysws(row, ship_node, ships)
      return if approved.nil?

      if row.gone && row.reached == "ysws"
        leak(row, "ysws_approved", approved, ships)
        return
      end

      net = add_integrity(row, approved, ships)
      return if net.nil?

      add_airtable(row, net, ships, from: row.hardware ? "integrity_skipped" : "integrity_passed")
    end

    # A rejected ship event is an admin forcing the project state, so it wins
    # over whatever the latest review row says. Without a review row (ships
    # older than the review queue) the ship event's own status stands in.
    # Deleted work only gets this far when it was approved before it went, so
    # it reads as approved whatever the review row says now.
    def ship_cert_node(row)
      return row.bounced ? "ship_approved_after_return" : "ship_approved" if row.gone
      return "ship_rejected" if row.certification_status == "rejected"
      return "ship_misfiled" if row.certification_status == "misfiled"

      case row.review_status
      when nil
        { "approved" => "ship_approved", "returned" => "ship_returned" }.fetch(row.certification_status, "ship_pending")
      when "pending" then row.bounced ? "ship_resubmitted" : "ship_pending"
      when "approved" then row.bounced ? "ship_approved_after_return" : "ship_approved"
      when "returned" then "ship_returned"
      when "misfiled" then "ship_misfiled"
      when "withdrawn" then "ship_withdrawn"
      else "ship_pending"
      end
    end

    # Returns the approved hours that carry on to integrity, or nil when the
    # ship stops here.
    def add_ysws(row, from, ships)
      unless row.ysws_reviewed && !row.ysws_returned
        hold(row, from, "ysws_pending", row.hours, ships)
        return nil
      end

      hold(row, from, "ysws_pending", row.unreviewed_hours, 0) if row.unreviewed_hours.positive?
      flow(from, "ysws_rejected", hours: row.rejected_hours, affected: row) if row.rejected_hours.positive?
      flow(from, "ysws_marked_down", hours: row.marked_down_hours, affected: row) if row.marked_down_hours.positive?
      @details["auto_rejected_hours"] += row.auto_rejected_hours

      if row.approved_minutes_all < ::Certification::Ysws::MIN_APPROVED_MINUTES
        flow(from, "ysws_under_minimum", hours: row.approved_hours, ships: ships)
        return nil
      end

      flow(from, "ysws_approved", hours: row.approved_hours, ships: ships)
      row.approved_hours
    end

    # Hardware never gets an integrity check (the Airtable sync doesn't wait
    # for one either), so its approved hours pass straight through.
    def add_integrity(row, approved, ships)
      if row.hardware
        flow("ysws_approved", "integrity_skipped", hours: approved, ships: ships)
        return approved
      end

      case row.integrity_status
      when *INTEGRITY_PASSED
        flow("ysws_approved", "integrity_passed", hours: approved, ships: ships)
        approved
      when "banned"
        flow("ysws_approved", "integrity_banned", hours: approved, ships: ships)
        nil
      when "deducted"
        deducted = [ row.deduction_minutes.to_i / 60.0, approved ].min
        flow("ysws_approved", "integrity_deducted", hours: deducted, affected: row)
        flow("ysws_approved", "integrity_passed", hours: approved - deducted, ships: ships)
        approved - deducted
      else
        hold(row, "ysws_approved", "integrity_pending", approved, ships)
        nil
      end
    end

    def add_airtable(row, net, ships, from:)
      unless row.airtable_synced
        hold(row, from, "airtable_unsynced", net, ships)
        return
      end

      flow(from, "airtable_synced", hours: net, ships: ships)
      if row.gone
        leak(row, "airtable_synced", net, ships)
        return
      end

      if row.in_unified_db
        @details["unified_db_hours"] += net
        @details["unified_db_ships"] += 1
      end

      over_cap = [ row.certified_over_cap_hours, net ].min
      flow("airtable_synced", "over_payout_cap", hours: over_cap, affected: row) if over_cap.positive?
      flow("airtable_synced", "payout_basis", hours: net - over_cap)
    end

    # The raw cap figure: time above ten hours on any single devlog inside a
    # shipped window. Certification does not cap, payout does, so this is what
    # the payout curve will never see whatever the reviewers approve.
    def record_payout_cap(row)
      return unless row.raw_over_cap_hours.positive?

      @details["raw_over_cap_hours"] += row.raw_over_cap_hours
      @details["raw_over_cap_devlogs"] += row.over_cap_devlogs
      @details["raw_over_cap_ships"] += 1
    end

    # Deleted work never sits in a waiting state: what would be held is what
    # it had reached when it went.
    def hold(row, from, held_node, hours, ships)
      return leak(row, from, hours, ships) if row.gone

      flow(from, held_node, hours: hours, ships: ships)
    end

    def leak(row, from, hours, ships)
      flow(from, row.gone_node, hours: hours, ships: ships, affected: (row unless row.whole_ship?))
    end

    def flow(source, target, hours:, ships: 0, affected: nil)
      @hours[target] += hours
      @ships[target] += ships
      @ships_affected[target] << affected.ship_event_id if affected
      link = @links[[ source, target ]]
      link[:hours] += hours
      link[:ships] += ships
    end

    # ---- SQL ---------------------------------------------------------------

    def ship_rows
      ::ActiveRecord::Base.connection.select_all(ship_rows_sql).map do |row|
        ShipRow.new(
          ship_event_id: row["ship_event_id"],
          hardware: row["hardware"],
          gone: row["gone"],
          reached: row["reached"],
          certification_status: row["certification_status"],
          review_status: row["review_status"] && SHIP_STATUSES[row["review_status"]],
          recert_from_ysws: row["recert_from_ysws"],
          bounced: row["bounced"],
          ysws_reviewed: row["reviewed_at"].present?,
          ysws_returned: row["returned_at"].present?,
          approved_minutes_all: row["approved_minutes_all"].to_i,
          airtable_synced: row["airtable_synced_at"].present?,
          in_unified_db: row["in_unified_db"].present?,
          integrity_status: row["integrity_status"] && INTEGRITY_STATUSES[row["integrity_status"]],
          deduction_minutes: row["deduction_minutes"],
          hours: row["hours"].to_f,
          devlogs: row["devlogs"].to_i,
          raw_over_cap_hours: row["raw_over_cap_hours"].to_f,
          over_cap_devlogs: row["over_cap_devlogs"].to_i,
          rejected_hours: row["rejected_hours"].to_f,
          auto_rejected_hours: row["auto_rejected_hours"].to_f,
          approved_hours: row["approved_hours"].to_f,
          marked_down_hours: row["marked_down_hours"].to_f,
          unreviewed_hours: row["unreviewed_hours"].to_f,
          certified_over_cap_hours: row["certified_over_cap_hours"].to_f
        )
      end
    end

    # Every devlog, deleted or not, with the ship event whose window it falls
    # in: the earliest ship posted at or after the devlog, which is exactly
    # Post::ShipEvent#window_devlogs read from the other side. Each devlog
    # also carries why and when it went, if it did: a banned owner and a
    # deleted project both stamp the project's deleted_at onto the devlogs, so
    # that moment is the project's, and an ordinary deletion is the devlog's.
    def devlog_base_sql
      <<~SQL
        WITH funnel_projects AS (
          SELECT projects.id,
                 projects.deleted_at,
                 (projects.hardware_stage IS NOT NULL) AS hardware,
                 CASE
                   WHEN projects.deleted_at IS NULL THEN NULL
                   WHEN EXISTS (
                     SELECT 1 FROM project_memberships pm
                     JOIN users u ON u.id = pm.user_id
                     WHERE pm.project_id = projects.id AND pm.role = #{::Project::Membership.roles[:owner]} AND u.banned
                   ) THEN 'banned'
                   ELSE 'project_deleted'
                 END AS gone
          FROM projects
        ),
        ship_posts AS (
          SELECT p.postable_id AS ship_event_id, p.project_id, p.created_at AS shipped_at
          FROM posts p
          JOIN funnel_projects pr ON pr.id = p.project_id
          WHERE p.postable_type = 'Post::ShipEvent'
        ),
        devlogs AS (
          SELECT d.id AS devlog_id,
                 COALESCE(d.duration_seconds, 0) / 3600.0 AS hours,
                 d.phase,
                 pr.hardware,
                 COALESCE(pr.gone, CASE WHEN d.deleted_at IS NOT NULL THEN 'devlog_deleted' END) AS gone,
                 COALESCE(pr.deleted_at, d.deleted_at) AS gone_at,
                 ship.ship_event_id,
                 ship.shipped_at,
                 EXISTS (SELECT 1 FROM ship_posts sp WHERE sp.project_id = p.project_id) AS project_has_ship
          FROM post_devlogs d
          JOIN posts p ON p.postable_type = 'Post::Devlog' AND p.postable_id = d.id
          JOIN funnel_projects pr ON pr.id = p.project_id
          LEFT JOIN LATERAL (
            SELECT sp.ship_event_id, sp.shipped_at
            FROM ship_posts sp
            WHERE sp.project_id = p.project_id AND sp.shipped_at >= p.created_at
            ORDER BY sp.shipped_at
            LIMIT 1
          ) ship ON TRUE
        )
      SQL
    end

    def devlog_stage_sql
      <<~SQL
        #{devlog_base_sql}
        SELECT
          COUNT(*) AS devlogs,
          COALESCE(SUM(hours), 0) AS gross,
          COALESCE(SUM(hours) FILTER (WHERE gone = 'banned' AND NOT shipped_before_gone), 0) AS banned_before_ship,
          COALESCE(SUM(hours) FILTER (WHERE gone = 'project_deleted' AND NOT shipped_before_gone), 0) AS project_deleted_before_ship,
          COALESCE(SUM(hours) FILTER (WHERE gone = 'devlog_deleted' AND NOT shipped_before_gone), 0) AS devlog_deleted_before_ship,
          COALESCE(SUM(hours) FILTER (WHERE gone IS NULL AND ship_event_id IS NULL AND NOT project_has_ship), 0) AS unshipped_never,
          COALESCE(SUM(hours) FILTER (WHERE gone IS NULL AND ship_event_id IS NULL AND project_has_ship), 0) AS unshipped_after_ship,
          COALESCE(SUM(hours) FILTER (WHERE ship_event_id IS NOT NULL AND (gone IS NULL OR shipped_before_gone)), 0) AS shipped,
          COALESCE(SUM(hours) FILTER (WHERE hardware), 0) AS hardware,
          COALESCE(SUM(hours) FILTER (WHERE phase = 'design'), 0) AS design_phase
        FROM (
          SELECT *, (ship_event_id IS NOT NULL AND shipped_at <= gone_at) AS shipped_before_gone FROM devlogs
        ) devlogs
      SQL
    end

    # The stage a deleted devlog had reached when it went: the deepest stage
    # whose own timestamp comes first. An auto-rejection at ban time stamps
    # reviewed_at after the project's deleted_at, so it does not count as a
    # review the work reached.
    def reached_sql(gone_at)
      <<~SQL.squish
        CASE
          WHEN times.synced_at <= #{gone_at} THEN 'airtable'
          WHEN times.reviewed_at <= #{gone_at} THEN 'ysws'
          WHEN times.approved_at <= #{gone_at} THEN 'ship_approved'
          ELSE 'shipped'
        END
      SQL
    end

    # One row per ship segment: the latest ship review, the latest YSWS
    # review, the integrity check, and the segment's devlogs rolled up. A
    # devlog review's approved hours are the devlog's own hours unless the
    # reviewer marked it down, so an untouched devlog never shows a rounding
    # sliver as a markdown.
    def ship_rows_sql
      <<~SQL
        #{devlog_base_sql},
        ship_reviews AS (
          SELECT DISTINCT ON (post_ship_event_id) post_ship_event_id, status, returned_by_id
          FROM certification_ship_reviews
          WHERE post_ship_event_id IS NOT NULL
          ORDER BY post_ship_event_id, id DESC
        ),
        bounced AS (
          SELECT DISTINCT post_ship_event_id
          FROM certification_ship_reviews
          WHERE status = #{::Certification::Ship.statuses[:returned]} OR returned_by_id IS NOT NULL
        ),
        ysws AS (
          SELECT DISTINCT ON (post_ship_event_id) id, post_ship_event_id, reviewed_at, returned_at,
                 airtable_synced_at, in_unified_db
          FROM certification_ysws_reviews
          ORDER BY post_ship_event_id, id DESC
        ),
        stage_times AS (
          SELECT sp.ship_event_id,
                 COALESCE(
                   (SELECT MIN(r.decided_at) FROM certification_ship_reviews r
                     WHERE r.post_ship_event_id = sp.ship_event_id AND r.status = #{::Certification::Ship.statuses[:approved]}),
                   CASE WHEN se.certification_status = 'approved'
                         AND NOT EXISTS (SELECT 1 FROM certification_ship_reviews r WHERE r.post_ship_event_id = sp.ship_event_id)
                        THEN sp.shipped_at END
                 ) AS approved_at,
                 y.reviewed_at,
                 y.airtable_synced_at AS synced_at
          FROM ship_posts sp
          JOIN post_ship_events se ON se.id = sp.ship_event_id
          LEFT JOIN ysws y ON y.post_ship_event_id = sp.ship_event_id
        ),
        shipped_devlogs AS (
          SELECT dl.ship_event_id, dl.hours, dl.gone,
                 CASE WHEN dl.gone IS NOT NULL THEN #{reached_sql("dl.gone_at")} END AS reached,
                 dr.status AS review_status, dr.justification,
                 CASE
                   WHEN dr.status IS DISTINCT FROM 'approved' THEN NULL
                   WHEN dr.approved_minutes >= dr.original_minutes THEN dl.hours
                   ELSE LEAST(dr.approved_minutes / 60.0, dl.hours)
                 END AS approved_hours
          FROM devlogs dl
          JOIN stage_times times ON times.ship_event_id = dl.ship_event_id
          LEFT JOIN ysws y ON y.post_ship_event_id = dl.ship_event_id
          LEFT JOIN certification_devlog_reviews dr ON dr.ysws_review_id = y.id AND dr.post_devlog_id = dl.devlog_id
          WHERE dl.ship_event_id IS NOT NULL AND (dl.gone IS NULL OR dl.shipped_at <= dl.gone_at)
        ),
        segments AS (
          SELECT ship_event_id, gone, reached,
                 COUNT(*) AS devlogs,
                 SUM(hours) AS hours,
                 SUM(GREATEST(hours - #{PAYOUT_CAP_HOURS}, 0)) AS raw_over_cap_hours,
                 COUNT(*) FILTER (WHERE hours > #{PAYOUT_CAP_HOURS}) AS over_cap_devlogs,
                 COALESCE(SUM(hours) FILTER (WHERE review_status = 'rejected'), 0) AS rejected_hours,
                 COALESCE(SUM(hours) FILTER (WHERE review_status = 'rejected'
                                               AND justification IN (#{AUTO_REJECT_JUSTIFICATIONS.map { |j| ::ActiveRecord::Base.connection.quote(j) }.join(", ")})), 0) AS auto_rejected_hours,
                 COALESCE(SUM(approved_hours), 0) AS approved_hours,
                 COALESCE(SUM(GREATEST(hours - approved_hours, 0)) FILTER (WHERE review_status = 'approved'), 0) AS marked_down_hours,
                 COALESCE(SUM(hours) FILTER (WHERE review_status IS NULL OR review_status = 'pending'), 0) AS unreviewed_hours,
                 COALESCE(SUM(GREATEST(approved_hours - #{PAYOUT_CAP_HOURS}, 0)), 0) AS certified_over_cap_hours
          FROM shipped_devlogs
          GROUP BY ship_event_id, gone, reached
        )
        SELECT sp.ship_event_id,
               pr.hardware,
               COALESCE(seg.gone, pr.gone) AS gone,
               COALESCE(seg.reached, CASE WHEN pr.gone IS NOT NULL THEN #{reached_sql("pr.deleted_at")} END) AS reached,
               se.certification_status,
               r.status AS review_status,
               (r.returned_by_id IS NOT NULL) AS recert_from_ysws,
               (b.post_ship_event_id IS NOT NULL) AS bounced,
               y.reviewed_at, y.returned_at, y.airtable_synced_at, y.in_unified_db,
               (SELECT COALESCE(SUM(approved_minutes), 0) FROM certification_devlog_reviews dr WHERE dr.ysws_review_id = y.id) AS approved_minutes_all,
               i.status AS integrity_status,
               i.deduction_minutes,
               COALESCE(seg.devlogs, 0) AS devlogs,
               COALESCE(seg.hours, 0) AS hours,
               COALESCE(seg.raw_over_cap_hours, 0) AS raw_over_cap_hours,
               COALESCE(seg.over_cap_devlogs, 0) AS over_cap_devlogs,
               COALESCE(seg.rejected_hours, 0) AS rejected_hours,
               COALESCE(seg.auto_rejected_hours, 0) AS auto_rejected_hours,
               COALESCE(seg.approved_hours, 0) AS approved_hours,
               COALESCE(seg.marked_down_hours, 0) AS marked_down_hours,
               COALESCE(seg.unreviewed_hours, 0) AS unreviewed_hours,
               COALESCE(seg.certified_over_cap_hours, 0) AS certified_over_cap_hours
        FROM ship_posts sp
        JOIN funnel_projects pr ON pr.id = sp.project_id
        JOIN post_ship_events se ON se.id = sp.ship_event_id
        JOIN stage_times times ON times.ship_event_id = sp.ship_event_id
        LEFT JOIN ship_reviews r ON r.post_ship_event_id = sp.ship_event_id
        LEFT JOIN bounced b ON b.post_ship_event_id = sp.ship_event_id
        LEFT JOIN ysws y ON y.post_ship_event_id = sp.ship_event_id
        LEFT JOIN certification_integrities i ON i.ship_event_id = sp.ship_event_id
        LEFT JOIN segments seg ON seg.ship_event_id = sp.ship_event_id
        ORDER BY sp.ship_event_id, seg.gone NULLS FIRST, seg.reached
      SQL
    end
  end
end
