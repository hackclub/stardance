class AddCertificateCreditsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :certificate_credit_hours, :decimal, precision: 12, scale: 2, default: 0, null: false
    add_column :users, :certificate_credit_projects, :integer, default: 0, null: false
  end
end
