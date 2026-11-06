module Virality
  class ReconcileBonus
    CREATED_BY = "virality_bonus"
    GOOD_BONUS = 50
    MAX_PROJECT_BONUS = 5_000

    def initialize(project)
      @project = project
    end

    def tier(excluding: nil, adding: nil)
      mentions = @project.mentions.approved
      mentions = mentions.where.not(id: excluding.id) if excluding
      tiers = mentions.pluck(:approved_tier) + [ adding ]
      return "great" if tiers.include?("great")
      "good" if tiers.include?("good")
    end

    def preview(tier: self.tier)
      amounts = Hash.new(0)
      ships = []
      if tier.present?
        # The flat reward belongs to the project's earliest owner. Ship top-ups
        # go to the same recipients as their original payouts.
        owner = @project.memberships.owner.order(:id).first&.user
        raise ArgumentError, "This project needs an owner before a bonus can be paid" unless owner && !owner.banned?

        amounts[owner.id] = GOOD_BONUS
        if tier == "great"
          remaining = MAX_PROJECT_BONUS - GOOD_BONUS
          @project.ship_events.approved.where.not(payout: nil).includes(:mission_submission, post: :user).order(:id).each do |ship|
            extra = [ ship.virality_extra_payout, remaining ].min
            next unless extra.positive?
            raise ArgumentError, "Ship ##{ship.id} has no eligible payout recipient" unless ship.payout_recipient && !ship.payout_recipient.banned?

            amounts[ship.payout_recipient.id] += extra
            remaining -= extra
            ships << { id: ship.id, percentile: ship.payout_basis_percentile, hours: ship.hours_at_payout, extra: extra }
          end
        end
      end

      paid = entries.group(:user_id).sum(:amount)
      changes = (paid.keys | amounts.keys).to_h { |id| [ id, amounts[id] - paid.fetch(id, 0) ] }
      { tier: tier, amounts: amounts, changes: changes, total: amounts.values.sum, delta: changes.values.sum, ships: ships }
    end

    def call
      @project.with_lock do
        result = preview
        result[:changes].sort.each do |user_id, amount|
          next if amount.zero?

          LedgerEntry.create!(
            ledgerable: @project, user_id: user_id, amount: amount,
            created_by: CREATED_BY,
            reason: "Virality #{amount.positive? ? 'bonus' : 'reversal'}: #{@project.title}"
          )
        end
        sync_achievements(result)
        if result[:changes].values.any? { |amount| !amount.zero? }
          PaperTrail::Version.create!(item: @project, event: "virality_bonus_reconciled",
            whodunnit: PaperTrail.request.whodunnit, object_changes: result.to_json)
        end
        result
      end
    end

    private

    def entries
      LedgerEntry.where(ledgerable: @project, created_by: CREATED_BY)
    end

    def sync_achievements(result)
      # Include former recipients when a project loses a tier. An achievement
      # survives reversal if another approved project still earns that tier.
      User.where(id: result[:changes].keys | result[:amounts].keys).order(:id).each do |user|
        user.with_lock do
          project_ids = LedgerEntry.where(user: user, ledgerable_type: "Project", created_by: CREATED_BY)
            .group(:ledgerable_id).having("SUM(amount) > 0").pluck(:ledgerable_id)
          tiers = ProjectMention.approved.where(project_id: project_ids).pluck(:approved_tier)
          { viral_good: tiers.any?, viral_great: tiers.include?("great") }.each do |slug, earned|
            if earned
              user.award_achievement!(slug)
            else
              user.revoke_achievement!(slug)
            end
          end
        end
      end
    end
  end
end
