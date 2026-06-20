class AddOutpostDiscountStardustToUsers < ActiveRecord::Migration[8.1]
  def change
    # Cumulative Stardust discount toward the Outpost Ticket, accrued 2 per
    # unrequested dollar on approved funding requests. Overflow past the ticket
    # base becomes a flight stipend.
    add_column :users, :outpost_discount_stardust, :integer, default: 0, null: false
  end
end
