class AddDevlogReviewIdToPostDevlogs < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :post_devlogs, :devlog_review, null: true, index: { algorithm: :concurrently }
  end
end
