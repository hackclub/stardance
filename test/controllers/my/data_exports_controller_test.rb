require "test_helper"

class My::DataExportsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob = create_user(slack_id: "U_BOB", display_name: "bob")
    sign_in(@alice)
  end

  test "index renders the export page" do
    get my_data_exports_path
    assert_response :success
    assert_select "h1", text: "Export My Data"
  end

  test "create enqueues an export job" do
    assert_enqueued_with job: User::DataExportJob do
      post my_data_exports_path
    end

    assert_equal 1, @alice.data_exports.count
    assert_response :redirect
  end

  test "create blocks when an export is already in progress" do
    @alice.data_exports.create!(status: "processing")

    assert_no_enqueued_jobs only: User::DataExportJob do
      post my_data_exports_path
    end

    assert_equal 1, @alice.data_exports.count
  end

  test "create replaces a stale active export" do
    stale_export = @alice.data_exports.create!(status: "processing")
    stale_export.update_column(:updated_at, User::DataExport::STALE_AFTER.ago - 1.minute)

    assert_enqueued_with job: User::DataExportJob do
      post my_data_exports_path
    end

    assert_predicate stale_export.reload, :failed?
    assert_equal 1, @alice.data_exports.pending_or_processing.count
  end

  test "create marks the export failed when enqueueing fails" do
    User::DataExportJob.stub(:perform_later, false) do
      post my_data_exports_path
    end

    export = @alice.data_exports.last
    assert_predicate export, :failed?
    assert_equal "The export could not be queued. Please try again.", export.error_message
    assert_redirected_to my_data_exports_path
    assert_equal "Your data export could not be queued. Please try again.", flash[:alert]
  end

  test "show redirects to the zip when download is available" do
    export = @alice.data_exports.create!(status: "completed")
    export.zip_file.attach(
      io: StringIO.new("fake zip"),
      filename: "export.zip",
      content_type: "application/zip"
    )

    get my_data_export_path(export)
    assert_response :redirect
    assert_match(/rails\/active_storage/, response.redirect_url)
  end

  test "show refuses downloads that are not ready" do
    export = @alice.data_exports.create!(status: "pending")

    get my_data_export_path(export)
    assert_redirected_to my_data_exports_path
  end

  test "show refuses expired downloads" do
    export = @alice.data_exports.create!(status: "completed", created_at: 8.days.ago)
    export.zip_file.attach(
      io: StringIO.new("fake zip"),
      filename: "export.zip",
      content_type: "application/zip"
    )

    get my_data_export_path(export)

    assert_redirected_to my_data_exports_path
    assert_equal "This export has expired and is no longer available.", flash[:alert]
  end

  test "destroy deletes the current user's export" do
    export = @alice.data_exports.create!(status: "completed")

    assert_difference -> { @alice.data_exports.count }, -1 do
      delete my_data_export_path(export)
    end

    assert_redirected_to my_data_exports_path
    assert_equal "Your data export has been deleted.", flash[:notice]
  end

  test "destroy cannot delete another user's export" do
    export = @bob.data_exports.create!(status: "completed")

    assert_no_difference -> { @bob.data_exports.count } do
      delete my_data_export_path(export)
    end

    assert_response :not_found
  end

  test "show cannot download another user's export" do
    export = @bob.data_exports.create!(status: "completed")

    get my_data_export_path(export)
    assert_response :not_found
  end

  test "logged out users are bounced" do
    delete logout_path
    get my_data_exports_path
    assert_response :redirect
  end
end
