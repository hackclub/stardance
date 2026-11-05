module Admin
  # Reclassifies historical work and reconciles the corrected payout against
  # recorded compensation. Paid snapshots and ledger entries remain immutable.
  class DevlogPhaseChange
    class Error < StandardError; end

    ADJUSTMENT_SOURCE = "admin_devlog_phase_adjustment"

    def initialize(project, actor:, phases:, reason:)
      @project = project
      @actor = actor
      @phases = phases.transform_keys(&:to_s).compact_blank
      @reason = reason.to_s.strip
    end

    def preview
      with_locked_records { build_preview }
    end

    def apply!(fingerprint:)
      with_locked_records do
        result = build_preview
        raise Error, "The project changed since this preview. Preview the changes again." unless fingerprint == result[:fingerprint]
        blockers = result[:ships].flat_map { |ship| ship[:blockers] }
        raise Error, blockers.uniq.to_sentence if blockers.any?

        ::PaperTrail.request(whodunnit: @actor.id.to_s) do
          result[:changes].each do |change|
            devlog = @devlogs.find { |row| row.id == change[:id] }
            devlog.phase = change[:to]
            # Historical content/attachments need not satisfy today's composer
            # validations. The phase was validated above; callbacks/audits run.
            devlog.save!(validate: false)
          end

          result[:ships].each do |row|
            ship = @ships.find { |record| record.id == row[:id] }
            ship.recalculate_hours_at_ship
            if row[:payment] == "paid" && row[:adjustment] != 0
              entry = LedgerEntry.create!(
                ledgerable: ship, user: ship.payout_recipient, amount: row[:adjustment],
                created_by: ADJUSTMENT_SOURCE,
                reason: [ "Devlog phase correction for ship ##{ship.id}", @reason.presence ].compact.join(": ")
              )
              row[:ledger_entry_id] = entry.id
            elsif row[:payment] == "locked"
              ship.update!(hours_at_payout: row[:after_hours])
            end
          end

          ::PaperTrail::Version.create!(
            item: @project, event: "devlog_phases_changed", whodunnit: @actor.id.to_s,
            object_changes: { reason: [ nil, @reason ], devlogs: [ nil, result[:changes] ], ships: [ nil, result[:ships] ] }.to_json
          )
        end
        result
      end
    end

    private

    def with_locked_records
      raise Error, "Only admins can reassign devlog phases." unless @actor.admin?
      raise Error, "The reason must be at most 1,000 characters." if @reason.length > 1_000
      unless @phases.any? && @phases.all? { |id, phase| id.match?(/\A[1-9]\d*\z/) && Post::Devlog::PHASES.include?(phase) }
        raise Error, "Choose design or build for at least one devlog."
      end

      # Ordinary shipping locks the project; ordinary payout issuance locks the
      # ship before touching its project. NOWAIT prevents a lock-order deadlock.
      @project.with_lock("FOR UPDATE NOWAIT", requires_new: true) do
        raise Error, "Only live hardware projects can be corrected." unless @project.hardware? && !@project.deleted?
        @state = [ @project.attributes ]
        @posts = lock_records(@project.posts)
        @devlogs = lock_records(Post::Devlog.unscoped.where(id: @posts.select { |p| p.postable_type == "Post::Devlog" }.map(&:postable_id)))
        @ships = lock_records(Post::ShipEvent.where(id: @posts.select { |p| p.postable_type == "Post::ShipEvent" }.map(&:postable_id)))
        @reviews = lock_records(::Certification::Ysws.where(post_ship_event_id: @ships.map(&:id)))
        @devlog_reviews = lock_records(::Certification::Devlog.where(ysws_review_id: @reviews.map(&:id)))
        lock_records(@project.certification_funding_requests)
        @entries = lock_records(LedgerEntry.where(ledgerable_type: "Post::ShipEvent", ledgerable_id: @ships.map(&:id)))
        lock_records(Mission::Submission.with_deleted.where(ship_event_id: @ships.map(&:id)))
        lock_records(::Certification::Integrity.where(ship_event_id: @ships.map(&:id)))
        lock_records(User.where(id: @posts.map(&:user_id).compact))
        @manual_entries = lock_records(LedgerEntry.where(ledgerable_type: "User", user_id: @posts.map(&:user_id).compact))
        yield
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      raise Error, "This project is being updated. Please preview again in a moment."
    end

    def lock_records(scope)
      records = scope.reorder(:id).lock("FOR UPDATE NOWAIT").to_a
      @state << records.map(&:attributes)
      records
    end

    def build_preview
      selected = @devlogs.select { |row| @phases.key?(row.id.to_s) && !row.deleted? }
      raise Error, "Choose only live devlogs belonging to this project." unless selected.size == @phases.size
      changes = selected.filter_map do |devlog|
        { id: devlog.id, from: devlog.phase, to: @phases.fetch(devlog.id.to_s) } if devlog.phase != @phases.fetch(devlog.id.to_s)
      end
      raise Error, "The selected devlogs already have those phases." if changes.empty?

      ship_posts = @posts.select { |p| p.postable_type == "Post::ShipEvent" }.sort_by { |p| [ p.created_at, p.id ] }
      changed_posts = @posts.select { |p| p.postable_type == "Post::Devlog" && changes.any? { |c| c[:id] == p.postable_id } }
      if ship_posts.map(&:created_at).uniq.size != ship_posts.size || changed_posts.any? { |p| ship_posts.any? { |s| s.created_at == p.created_at } }
        raise Error, "A devlog or ship sits on an ambiguous ship-window boundary. Resolve its timestamp before reassigning phases."
      end
      affected_ids = changed_posts.filter_map { |p| ship_posts.find { |s| s.created_at > p.created_at }&.postable_id }.uniq
      overrides = changes.to_h { |change| [ change[:id], change[:to] ] }
      rows = @ships.select { |ship| affected_ids.include?(ship.id) }.map { |ship| preview_ship(ship, overrides) }

      {
        changes: changes, ships: rows,
        fingerprint: Digest::SHA256.hexdigest([ @state, @phases.sort, @reason, @actor.id, rows ].to_json)
      }
    end

    def preview_ship(ship, overrides)
      before_hours = ship.hours
      after_hours = ship.hours(phase_overrides: overrides)
      payment = if ship.mission_submission&.payout_path == "static_prize"
        "static"
      elsif ship.payout.present?
        "paid"
      elsif ship.payout_basis_locked_at?
        "locked"
      else
        "unpaid"
      end
      row = {
        id: ship.id, recipient: ship.payout_recipient&.display_name, payment: payment,
        before_hours: before_hours, after_hours: after_hours,
        before_amount: payment == "locked" ? ship.estimated_payout : ship.payout_amount_for(before_hours, ship.multiplier, ship.payout_blessing),
        after_amount: ship.payout_amount_for(after_hours, ship.multiplier, ship.payout_blessing),
        adjustment: 0, blockers: []
      }
      reviews = @reviews.select { |review| review.post_ship_event_id == ship.id }
      row[:blockers] << "Ship ##{ship.id} has multiple time reviews; reconcile its review history first." if reviews.size > 1
      devlog_reviews = @devlog_reviews.select { |review| reviews.map(&:id).include?(review.ysws_review_id) }
      eligible_ids = ship.payout_devlog_ids | ship.payout_devlog_ids(phase_overrides: overrides)
      if devlog_reviews.select { |review| eligible_ids.include?(review.post_devlog_id) }.group_by(&:post_devlog_id).any? { |_, rows| rows.size > 1 }
        row[:blockers] << "Ship ##{ship.id}: duplicate devlog reviews must be reconciled first."
      end
      if payment.in?(%w[paid locked]) && devlog_reviews.any?(&:reviewed?)
        reviewed_ids = devlog_reviews.select(&:reviewed?).map(&:post_devlog_id)
        if (eligible_ids - reviewed_ids).any?
          row[:blockers] << "Ship ##{ship.id}: finish reviewing the eligible build devlogs before adjusting its payout basis."
        end
      end
      return row unless payment == "paid"

      entries = @entries.select { |entry| entry.ledgerable_id == ship.id }
      originals = entries.select { |entry| entry.created_by == "ship_event_payout" }
      accounted = ship.payout + entries.select { |entry| entry.created_by == ADJUSTMENT_SOURCE }.sum(&:amount)
      row[:accounted_amount] = accounted
      row[:adjustment] = row[:after_amount] - accounted if row[:after_amount]

      if originals.size != 1 || originals.first.amount != ship.payout || entries.any? { |entry| entry.user_id != ship.payout_recipient&.id || ![ "ship_event_payout", ADJUSTMENT_SOURCE ].include?(entry.created_by) }
        row[:blockers] << "Ship ##{ship.id}: the original payout ledger or recipient does not reconcile."
      end
      manual_entries = @manual_entries.select do |entry|
        entry.user_id == ship.payout_recipient&.id && originals.first && entry.created_at >= originals.first.created_at
      end
      if manual_entries.any?
        row[:blockers] << "Ship ##{ship.id}: recipient has manual ledger entries (#{manual_entries.map { |entry| "##{entry.id}" }.join(', ')}) since payment. Reconcile these separately to avoid duplicate compensation."
      end
      unless ship.multiplier&.positive? && %w[neutral blessed cursed].include?(ship.payout_blessing) && ship.payout_curve_version == Post::ShipEvent::Payouts::HARDWARE_PAYOUT_CURVE_VERSION
        row[:blockers] << "Ship ##{ship.id}: a complete original hardware payout basis is required."
      end
      if ship.certification_status != "approved" || ship.payout_recipient.nil? || ship.payout_recipient.banned? || ship.integrity_check&.status.in?(%w[banned deducted])
        row[:blockers] << "Ship ##{ship.id}: resolve certification or fraud restrictions before changing its payout."
      end
      row
    end
  end
end
