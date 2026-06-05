class DropReportReviewTokens < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
       drop_table :report_review_tokens
    end
  end
end
