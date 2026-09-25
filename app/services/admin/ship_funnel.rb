# frozen_string_literal: true

module Admin
  class ShipFunnel
    Link = Struct.new(:kind, :source, :target, :hours, :ships)

    AIRTABLE_FIELDS = [ "review_id", "Automation - YSWS Record ID", "Automation - Error", "rejected_at" ].freeze

    def to_h
      @links = Hash.new { |links, key| links[key] = Link.new(*key, 0.0, 0) }
      @airtable = airtable_states
      ship_rows.each { |row| add_ship(row) }

      {
        links: @links.values.select { |link| link.hours.positive? || link.ships.positive? }.map(&:to_h),
        unshipped_links: unshipped_links,
        loops: loops,
        airtable_split: !@airtable.nil?
      }
    end

    private

    def add_ship(row)
      kind = row["hardware"] ? "hardware" : "software"
      hours = row["hours_at_ship"].to_f
      flow = ->(source, target, flow_hours, ships: 1) { add(kind, source, target, flow_hours, ships) }

      return flow.call("Shipped", "Fraud", hours) if row["fraud"]

      review, reship, waiting =
        if kind == "hardware"
          [ "Build review", "Reship, skipped review", "Waiting on build review" ]
        else
          [ "Shipwrights review", "Reship, skipped review", "Waiting on Shipwrights" ]
        end
      status = row["certification_status"]
      first = status != "approved" || row["was_reviewed"] ? review : reship
      flow.call("Shipped", first, hours)

      case status
      when "pending" then return flow.call(first, waiting, hours)
      when "returned" then return flow.call(first, row["returned_bucket"], hours)
      when "misfiled" then return flow.call(first, "Misfiled, back to design", hours)
      when "approved" then nil
      else return flow.call(first, "Rejected by ship review", hours)
      end

      # GOI sent it back: it's waiting on ship review again
      return flow.call(first, waiting, hours) if row["goi_outcome"] == "Sent back to ship review"

      flow.call(first, "GOI review", hours)
      return flow.call("GOI review", row["goi_outcome"], hours) unless row["goi_outcome"] == "Passed GOI"

      add_goi_deflation(row, kind, hours, flow)
      approved = row["approved_minutes"].to_f / 60

      check = kind == "hardware" ? "Hardware, skipped" : "Fraud check"
      flow.call("GOI review", check, approved)
      # fraud checks are only created by the daily 5am job, so a missing one is still waiting
      if kind == "software" && row["fraud_check_outcome"].in?([ "No fraud check created", "Waiting on fraud team" ])
        return flow.call(check, "Waiting on fraud team", approved)
      end

      deducted = row["deducted"] ? [ row["deduction_minutes"].to_f / 60, approved ].min : 0.0
      flow.call(check, "Deducted by fraud team", deducted, ships: 0)
      net = approved - deducted
      flow.call(check, "Airtable", net)
      return flow.call("Airtable", "Cleared, never synced", net) unless row["synced"]

      flow.call("Airtable", airtable_state(row["review_id"]), net) if @airtable
    end

    def add_goi_deflation(row, kind, hours, flow)
      claimed = row["claimed_minutes"].to_f / 60
      approved = row["approved_minutes"].to_f / 60
      flow.call("GOI review", "Deflated by GOI", claimed - approved, ships: 0)
      return if kind == "hardware"

      rounding = row["rounding_hours"].to_f
      flow.call("GOI review", "Whole-minute rounding", rounding, ships: 0)
      flow.call("GOI review", "Not reviewed by GOI", hours - claimed - rounding, ships: 0)
    end

    def add(kind, source, target, hours, ships)
      link = @links[[ kind, source, target ]]
      link.hours += hours
      link.ships += ships
    end

    def airtable_state(review_id)
      record = @airtable[review_id.to_s]
      return "Lost to key collision" unless record
      return "Unified" if record["Automation - YSWS Record ID"].present?
      return "Rejected by sync" if record["rejected_at"].present?

      error = record["Automation - Error"].to_s
      return "Waiting on final pass" if error.blank?

      error.match?(/unified|duplicate/i) ? "Duplicate in Unified" : "Final-pass error, fixable"
    end

    def airtable_states
      ::Certification::YswsAirtable.table.all(fields: AIRTABLE_FIELDS)
        .each_with_object({}) { |record, rows| rows[record["review_id"].to_s] ||= record if record["review_id"].present? }
    rescue Faraday::Error, Norairrecord::Error => error
      Rails.logger.warn("[ShipFunnel] Airtable unavailable: #{error.message}")
      nil
    end

    def loops
      {
        returned_twice: ::Certification::Ship.returned.group(:post_ship_event_id).having("count(*) >= 2").count.size,
        goi_sent_back: ::Certification::Ship.where.not(returned_by_id: nil).distinct.count(:post_ship_event_id),
        goi_twice: ::Certification::Ysws.group(:post_ship_event_id).having("count(*) >= 2").count.size
      }
    end

    def unshipped_links
      shipped = @links.values.select { |link| link.source == "Shipped" }.group_by(&:kind)
      links = shipped.map do |kind, from_shipped|
        { kind: kind, source: "Devlogged", target: "Shipped", hours: from_shipped.sum(&:hours), ships: from_shipped.sum(&:ships) }
      end
      rows = ::ActiveRecord::Base.connection.select_all(unshipped_sql).to_a
      links + rows.map { |row| { kind: row["hardware"] ? "hardware" : "software", source: "Devlogged", target: row["bucket"], hours: row["hours"].to_f, ships: 0 } }
    end

    def unshipped_sql
      <<~SQL
        SELECT hardware, bucket, sum(hours) AS hours
        FROM (
          SELECT pr.hardware_stage IS NOT NULL AS hardware,
                 coalesce(pd.duration_seconds, 0) / 3600.0 AS hours,
                 CASE WHEN u.banned OR pr.deleted_at IS NOT NULL THEN
                        CASE WHEN in_window THEN NULL ELSE 'Fraud before shipping' END
                      WHEN pd.deleted_at IS NOT NULL THEN 'Devlog deleted'
                      WHEN NOT in_window THEN 'Not shipped yet'
                      WHEN pr.hardware_stage IS NOT NULL AND pd.phase = 'design' THEN 'Design phase (hardware)'
                 END AS bucket
          FROM post_devlogs pd
          JOIN posts dp    ON dp.postable_type = 'Post::Devlog' AND dp.postable_id = pd.id
          JOIN projects pr ON pr.id = dp.project_id
          JOIN users u     ON u.id = dp.user_id
          CROSS JOIN LATERAL (
            SELECT EXISTS (SELECT 1 FROM posts sp WHERE sp.project_id = dp.project_id
                             AND sp.postable_type = 'Post::ShipEvent' AND sp.created_at >= dp.created_at) AS in_window
          ) w
        ) devlogs
        WHERE bucket IS NOT NULL
        GROUP BY 1, 2
      SQL
    end

    def ship_rows = ::ActiveRecord::Base.connection.select_all(ship_rows_sql).to_a

    def ship_rows_sql
      returned = ::Certification::Ship.statuses[:returned]
      <<~SQL
        SELECT y.id AS review_id,
               pr.hardware_stage IS NOT NULL AS hardware,
               se.hours_at_ship,
               coalesce(u.banned OR pr.deleted_at IS NOT NULL OR i.status = #{integrity(:banned)}, false) AS fraud,
               se.certification_status,
               EXISTS (SELECT 1 FROM certification_ship_reviews c WHERE c.post_ship_event_id = se.id) AS was_reviewed,
               CASE WHEN EXISTS (SELECT 1 FROM posts l WHERE l.project_id = p.project_id AND l.postable_type = 'Post::ShipEvent'
                                   AND l.created_at > p.created_at) THEN 'Cut off by a later ship'
                    WHEN (SELECT max(coalesce(decided_at, created_at)) FROM certification_ship_reviews c
                          WHERE c.post_ship_event_id = se.id AND c.status = #{returned}) > now() - interval '30 days'
                      THEN 'Returned, <30d ago'
                    ELSE 'Returned, >30d ago' END AS returned_bucket,
               CASE WHEN y.id IS NULL THEN 'Approved, no GOI review'
                    WHEN y.reviewed_at IS NULL AND y.returned_at IS NOT NULL THEN 'Sent back to ship review'
                    WHEN y.reviewed_at IS NULL THEN 'Waiting on GOI'
                    WHEN NOT EXISTS (SELECT 1 FROM certification_devlog_reviews d
                                     WHERE d.ysws_review_id = y.id AND d.status <> 'rejected') THEN 'Rejected by GOI'
                    ELSE 'Passed GOI' END AS goi_outcome,
               (SELECT sum(original_minutes) FROM certification_devlog_reviews d WHERE d.ysws_review_id = y.id) AS claimed_minutes,
               (SELECT coalesce(sum(approved_minutes), 0) FROM certification_devlog_reviews d WHERE d.ysws_review_id = y.id) AS approved_minutes,
               (SELECT sum(pd.duration_seconds / 3600.0 - d.original_minutes / 60.0)
                FROM certification_devlog_reviews d
                JOIN post_devlogs pd ON pd.id = d.post_devlog_id
                WHERE d.ysws_review_id = y.id AND pd.deleted_at IS NULL
                  AND pd.duration_seconds / 60 = d.original_minutes) AS rounding_hours,
               CASE WHEN i.status IS NULL THEN 'No fraud check created'
                    WHEN i.status = #{integrity(:pending)} THEN 'Waiting on fraud team'
                    ELSE 'Cleared' END AS fraud_check_outcome,
               i.status = #{integrity(:deducted)} AND pr.hardware_stage IS NULL AS deducted,
               i.deduction_minutes,
               y.airtable_synced_at IS NOT NULL AS synced
        FROM post_ship_events se
        JOIN posts p     ON p.postable_type = 'Post::ShipEvent' AND p.postable_id = se.id
        JOIN projects pr ON pr.id = p.project_id
        JOIN users u     ON u.id = p.user_id
        LEFT JOIN certification_integrities i ON i.ship_event_id = se.id
        LEFT JOIN certification_ysws_reviews y
          ON y.id = (SELECT max(id) FROM certification_ysws_reviews WHERE post_ship_event_id = se.id)
      SQL
    end

    def integrity(status) = ::Certification::Integrity.statuses.fetch(status)
  end
end
