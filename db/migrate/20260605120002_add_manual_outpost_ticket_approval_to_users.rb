class AddManualOutpostTicketApprovalToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :manual_outpost_ticket_approval, :string
  end
end
