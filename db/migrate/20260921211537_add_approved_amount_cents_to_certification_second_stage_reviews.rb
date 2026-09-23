class AddApprovedAmountCentsToCertificationSecondStageReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_second_stage_reviews, :approved_amount_cents, :integer
  end
end
