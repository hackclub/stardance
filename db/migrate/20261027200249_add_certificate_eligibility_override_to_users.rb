class AddCertificateEligibilityOverrideToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :certificate_eligibility_override, :boolean, default: false, null: false
  end
end
