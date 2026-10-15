class CreateCertificationMACAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_mac_analyses do |t|
      t.references :ysws_review, null: false, index: { unique: true },
        foreign_key: { to_table: :certification_ysws_reviews }
      t.jsonb :report, null: false, default: {}
      t.datetime :generated_at, null: false

      t.timestamps
    end
  end
end
