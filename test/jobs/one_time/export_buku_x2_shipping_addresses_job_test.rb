require "test_helper"
require "tmpdir"

class OneTime::ExportBukuX2ShippingAddressesJobTest < ActiveJob::TestCase
  setup do
    @directory = Dir.mktmpdir("shipping-export-test-")
    @input = File.join(@directory, "input.csv")
    @output = File.join(@directory, "output.csv")
    @user = users(:one)
    @user.hack_club_identity.update!(access_token: "fake-export-token")
    write_input(@user.id)
    @job = OneTime::ExportBukuX2ShippingAddressesJob.new
    @address = { "first_name" => "Test", "last_name" => "Person", "line_1" => "123 Example St",
                 "line_2" => "", "city" => "Example", "state" => "MA", "postal_code" => "00123", "country" => "US" }
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "dry run is the default and never contacts HCA" do
    HCAService.stub(:connection, -> { flunk "dry run must not contact HCA" }) do
      summary = @job.perform(input_path: @input, output_path: @output)
      assert_equal({ "ready" => 1 }, summary[:counts])
      assert summary[:dry_run]
      assert_nil output.first["line_1"]
    end
  end

  test "exports only whitelisted address fields with private permissions and no database changes" do
    with_response({ "identity" => { "addresses" => [ @address ], "birthday" => "2000-01-01", "phone_number" => "private-phone" } }) do
      assert_no_changes -> { @user.reload.attributes } do
        assert_equal({ "ok" => 1 }, run_export[:counts])
      end
    end
    assert_equal "00123", output.first["postal_code"]
    assert_equal @user.email, output.first["email"]
    assert_equal 0o600, File.stat(@output).mode & 0o777
    assert_equal OneTime::ExportBukuX2ShippingAddressesJob::HEADERS, output.headers
    refute_includes File.read(@output), "private-phone"
  end

  test "deduplicates participants and reports missing users" do
    write_input(@user.id, @user.id, 9_223_372_036_854_775_807)
    with_addresses([ @address ]) do
      summary = run_export
      assert_equal 3, summary[:input_rows]
      assert_equal 2, summary[:unique_users]
      assert_equal 1, summary[:duplicate_rows]
      assert_equal({ "ok" => 1, "user_not_found" => 1 }, summary[:counts])
    end
    assert_equal 2, output.size
  end

  test "selects an explicitly primary address" do
    with_addresses([ @address.merge("line_1" => "Old address"), @address.merge("primary" => true) ]) { run_export }
    assert_equal @address["line_1"], output.first["line_1"]
    assert_equal "2", output.first["address_count"]
  end

  test "does not guess among multiple addresses" do
    with_addresses([ @address, @address.merge("line_1" => "Other address") ]) { run_export }
    assert_equal "multiple_addresses", output.first["status"]
    assert_nil output.first["line_1"]
  end

  test "missing identity or token never makes a request" do
    @user.hack_club_identity.tap { |identity| identity.access_token = nil; identity.save!(validate: false) }
    HCAService.stub(:connection, -> { flunk "no token must not contact HCA" }) { run_export }
    assert_equal "no_access_token", output.first["status"]

    @user.hack_club_identity.destroy!
    @output = File.join(@directory, "second.csv")
    HCAService.stub(:connection, -> { flunk "no identity must not contact HCA" }) { run_export }
    assert_equal "no_hca_identity", output.first["status"]
  end

  test "handles HTTP failures without exposing response contents" do
    [ 401, 403, 429, 500 ].each do |status|
      @output = File.join(@directory, "http-#{status}.csv")
      with_response({ "error" => "sensitive response" }, status: status) { run_export }
      assert_equal "http_#{status}", output.first["status"]
      refute_includes File.read(@output), "sensitive response"
    end
  end

  test "handles absent malformed empty and incomplete addresses" do
    cases = [
      [ { "identity" => {} }, "address_field_unavailable" ],
      [ { "identity" => { "addresses" => [] } }, "no_address" ],
      [ { "identity" => { "addresses" => [ "invalid" ] } }, "invalid_response" ],
      [ { "identity" => { "addresses" => [ @address.except("line_1") ] } }, "incomplete_address" ],
      [ [], "invalid_response" ]
    ]
    cases.each_with_index do |(body, status), index|
      @output = File.join(@directory, "case-#{index}.csv")
      with_response(body) { run_export }
      assert_equal status, output.first["status"]
    end
  end

  test "handles timeout and malformed JSON without logging private details" do
    connection = Object.new
    connection.define_singleton_method(:get) { |*| raise Faraday::TimeoutError, "private-token" }
    HCAService.stub(:connection, connection) { @job.stub(:sleep, nil) { run_export } }
    assert_equal "request_failed", output.first["status"]
    refute_includes File.read(@output), "private-token"
    @output = File.join(@directory, "malformed.csv")
    with_response("not json", raw: true) { run_export }
    assert_equal "invalid_response", output.first["status"]
  end

  test "escapes spreadsheet formulas" do
    with_addresses([ @address.merge("first_name" => "=FAKE()", "line_2" => " @FAKE()") ]) { run_export }
    assert_equal "'=FAKE()", output.first["first_name"]
    assert_equal "' @FAKE()", output.first["line_2"]
  end

  test "invalid CSV is rejected before fetching or creating output" do
    File.write(@input, "user_id,username\nnot-an-id,private-name\n")
    HCAService.stub(:connection, -> { flunk "invalid CSV must not contact HCA" }) do
      error = assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
      refute_includes error.message, "private-name"
      refute File.exist?(@output)
    end
  end

  test "malformed CSV errors are sanitized and duplicate headers are rejected" do
    [ "user_id,username\n1,\"private-unclosed-value\n", "user_id,user_id\n1,2\n", "user_id,\n1,x\n" ].each do |contents|
      File.write(@input, contents)
      error = assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
      refute_includes error.message, "private-unclosed-value"
      assert_nil error.cause
      refute File.exist?(@output)
    end
  end

  test "accepts BOM CSV containing only user ids" do
    File.write(@input, "\uFEFFuser_id\n#{@user.id}\n")
    with_addresses([ @address ]) { assert_equal({ "ok" => 1 }, run_export[:counts]) }
  end

  test "completion logs and return value contain counts only" do
    logs = StringIO.new
    Rails.stub(:logger, ActiveSupport::Logger.new(logs)) do
      with_addresses([ @address ]) do
        summary = run_export
        [ @user.email, @address["line_1"], "fake-export-token", @input, @output ].each do |private_value|
          refute_includes logs.string, private_value
          refute_includes summary.to_json, private_value
        end
      end
    end
    assert_includes logs.string, "completed job_id="
  end

  test "multiple primary addresses and output symlinks are not trusted" do
    with_addresses([ @address.merge("primary" => true), @address.merge("primary" => true) ]) { run_export }
    assert_equal "multiple_addresses", output.first["status"]
    @output = File.join(@directory, "symlink.csv")
    File.symlink(@input, @output)
    before = File.read(@input)
    assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
    assert_equal before, File.read(@input)
  end

  test "will not overwrite a previous export or the input" do
    File.write(@output, "keep this")
    assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
    assert_equal "keep this", File.read(@output)
    @output = @input
    before = File.read(@input)
    assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
    assert_equal before, File.read(@input)
  end

  test "rejects public file permissions and application directories" do
    File.chmod(0o644, @input)
    assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
    File.chmod(0o600, @input)
    @output = Rails.root.join("public", "shipping-export.csv").to_s
    assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
    File.chmod(0o755, @directory)
    assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
  end

  test "unexpected exceptions have sanitized messages and no cause" do
    User.stub(:find_by, ->(*) { raise "private-data" }) do
      error = assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) { run_export }
      refute_includes error.message, "private-data"
      assert_nil error.cause
    end
  end

  test "job cannot be queued and does not log arguments" do
    refute @job.class.log_arguments
    assert_raises(OneTime::ExportBukuX2ShippingAddressesJob::ExportError) do
      OneTime::ExportBukuX2ShippingAddressesJob.perform_later(input_path: @input, output_path: @output)
    end
  end

  private
    def write_input(*ids)
      File.open(@input, "w", 0o600) do |file|
        file.write(CSV.generate { |csv| csv << [ "user_id", "username" ]; ids.each { |id| csv << [ id, "Example" ] } })
      end
    end

    def output
      CSV.read(@output, headers: true)
    end

    def run_export
      @job.perform(input_path: @input, output_path: @output, dry_run: false)
    end

    def with_addresses(addresses, &block)
      with_response({ "identity" => { "addresses" => addresses } }, &block)
    end

    def with_response(body, status: 200, raw: false)
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v1/me") do |env|
          assert_equal "Bearer fake-export-token", env.request_headers["Authorization"]
          assert_equal 15, env.request.timeout
          assert_equal 5, env.request.open_timeout
          [ status, {}, raw ? body : JSON.generate(body) ]
        end
      end
      connection = Faraday.new { |builder| builder.adapter :test, stubs }
      HCAService.stub(:connection, connection) { @job.stub(:sleep, nil) { yield } }
      stubs.verify_stubbed_calls
    end
end
