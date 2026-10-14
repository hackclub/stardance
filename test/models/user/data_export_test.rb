# == Schema Information
#
# Table name: user_data_exports
#
#  id            :bigint           not null, primary key
#  error_message :text
#  status        :string           default("pending"), not null
#  zip_filename  :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_user_data_exports_on_user_id             (user_id)
#  index_user_data_exports_on_user_id_active      (user_id) UNIQUE WHERE (((status)::text = 'pending'::text) OR ((status)::text = 'processing'::text))
#  index_user_data_exports_on_user_id_and_status  (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class User::DataExportTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @user = create_user(slack_id: "U_DATA_EXPORT", display_name: "data-exporter")
  end

  test "exports expire after seven days" do
    export = @user.data_exports.create!(status: "completed", created_at: 7.days.ago - 1.second)

    assert_predicate export, :expired?
    refute_predicate export, :download_available?
  end

  test "purge expired deletes only exports older than seven days" do
    expired_export = @user.data_exports.create!(status: "completed", created_at: 8.days.ago)
    expired_export.zip_file.attach(
      io: StringIO.new("fake zip"),
      filename: "expired.zip",
      content_type: "application/zip"
    )
    expired_blob_id = expired_export.zip_file.blob.id
    current_export = @user.data_exports.create!(status: "completed")

    perform_enqueued_jobs { User::DataExport.purge_expired! }

    refute User::DataExport.exists?(expired_export.id)
    refute ActiveStorage::Blob.exists?(expired_blob_id)
    assert User::DataExport.exists?(current_export.id)
  end
end
