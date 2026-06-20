class AddPhaseToPostDevlogs < ActiveRecord::Migration[8.1]
  def change
    # Records which hardware stage ("design"/"build") a devlog was logged in, so
    # the ship payout basis can count build-phase time only. Nil for software.
    add_column :post_devlogs, :phase, :string
  end
end
