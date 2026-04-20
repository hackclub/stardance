module LedgerEntriesHelper
  def ledger_entry_reason_with_link(entry)
    case entry.ledgerable
    when User::Achievement
      achievement = entry.ledgerable.achievement
      link_to entry.reason, my_achievements_path(highlight: achievement.slug), data: { turbo_frame: "_top" }
    when Post::ShipEvent
      project = entry.ledgerable.post&.project
      if project
        link_to entry.reason, project_path(project), data: { turbo_frame: "_top" }
      else
        entry.reason
      end
    when ShopOrder
      link_to entry.reason, shop_my_orders_path, data: { turbo_frame: "_top" }
    else
      entry.reason
    end
  end
end
