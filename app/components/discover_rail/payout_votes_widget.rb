# frozen_string_literal: true

module DiscoverRail
  # Discover-rail module showing how many community votes a project's latest
  # ship still needs before its payout unlocks. Reusable on any page that hands
  # it the precomputed hash via context, e.g.:
  #
  #   discover_rail_widgets :payout_votes,
  #                         context: -> { { votes_for_payout: @votes_for_payout } }
  #
  # The hash shape is { current:, required:, remaining: } (see
  # ProjectsController#prepare_project_show_context); nil hides the module.
  class PayoutVotesWidget < BaseWidget
    register_as :payout_votes

    def votes
      context[:votes_for_payout]
    end

    # Hardware owes no ratings and awaits none, so every step here would be
    # either already done or irrelevant.
    def render?
      votes.present? && !votes[:static_prize] && !votes[:paid_out] && !votes[:hardware]
    end
  end
end
