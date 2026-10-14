module RatingLifecycle
  class Backfill
    Result = Data.define(:scanned, :changed, :exact, :estimated, :unresolved)

    def initialize(scope: Post::ShipEvent.where(certification_status: "approved").or(Post::ShipEvent.where.not(payout: nil)), apply: false)
      @scope = scope
      @apply = apply
    end

    def call
      counts = Hash.new(0)

      @scope.find_each do |ship_event|
        counts[:scanned] += 1
        attributes, estimated = attributes_for(ship_event)
        quality = ship_event.lifecycle_data_quality.presence || (estimated ? "backfilled_estimated" : "backfilled_exact")

        if attributes.empty?
          counts[quality == "backfilled_estimated" ? :estimated : :exact] += 1 if ship_event.lifecycle_data_quality.present?
          counts[:unresolved] += 1 if ship_event.lifecycle_data_quality.blank?
          next
        end

        attributes[:lifecycle_data_quality] = quality if ship_event.lifecycle_data_quality.blank?
        counts[estimated ? :estimated : :exact] += 1
        counts[:changed] += 1

        ship_event.update_columns(**attributes, updated_at: ship_event.updated_at) if @apply
      end

      Result.new(
        scanned: counts[:scanned],
        changed: counts[:changed],
        exact: counts[:exact],
        estimated: counts[:estimated],
        unresolved: counts[:unresolved]
      )
    end

    private

    def attributes_for(ship_event)
      attributes = {}
      estimated = false

      if ship_event.voting_started_at.nil?
        started_at = certification_decided_at(ship_event) || audited_approval_at(ship_event)
        unless started_at
          started_at = ship_event.post&.created_at
          estimated = started_at.present?
        end
        attributes[:voting_started_at] = started_at if started_at
      end

      if ship_event.voting_completed_at.nil?
        completed_at = completion_time(ship_event)
        attributes[:voting_completed_at] = completed_at if completed_at
      end

      if ship_event.payout.present? && ship_event.paid_at.nil?
        paid_at = payout_ledger_time(ship_event) || audited_payout_at(ship_event)
        unless paid_at
          paid_at = ship_event.updated_at
          estimated = paid_at.present?
        end
        attributes[:paid_at] = paid_at if paid_at
      end

      [ attributes, estimated ]
    end

    def certification_decided_at(ship_event)
      Certification::Ship.approved
        .where(post_ship_event_id: ship_event.id)
        .where.not(decided_at: nil)
        .minimum(:decided_at)
    end

    def audited_approval_at(ship_event)
      audit_transition_time(ship_event, "certification_status") { |value| value == "approved" }
    end

    def audited_payout_at(ship_event)
      audit_transition_time(ship_event, "payout") { |value| value.present? }
    end

    def audit_transition_time(ship_event, field)
      ship_event.versions.order(:created_at).find do |version|
        change = version.changeset[field]
        change.is_a?(Array) && yield(change.last)
      rescue PaperTrail::VersionConcern::ObjectChangesAttributeError, Psych::Exception
        false
      end&.created_at
    end

    def completion_time(ship_event)
      votes = ship_event.payout_counted_votes
      return unless votes.size >= Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT

      votes.max_by { |vote| [ vote.created_at, vote.id ] }.created_at
    end

    def payout_ledger_time(ship_event)
      LedgerEntry.where(
        ledgerable_type: "Post::ShipEvent",
        ledgerable_id: ship_event.id,
        created_by: "ship_event_payout"
      ).minimum(:created_at)
    end
  end
end
