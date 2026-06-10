require "test_helper"

class Api::V1::Certification::ShipsControllerTest < ActionDispatch::IntegrationTest
  API_KEY = "test-shipwrights-key"

  setup do
    credentials_options[:certification_shipwrights] = { api_keys: [ API_KEY ] }

    @owner = create_user(slack_id: "U0OWNER", display_name: "owner")
    @reviewer = create_user(slack_id: "U0REVIEWER", display_name: "reviewer")

    @project = Project.create!(title: "certifiable")
    @project.memberships.create!(user: @owner, role: :owner)
    @ship = Certification::Ship.create!(project: @project)
  end

  test "rejects requests without a valid api key" do
    fetch_ships(key: nil)
    assert_response :unauthorized

    fetch_ships(key: "wrong-key")
    assert_response :unauthorized
  end

  test "returns ships in the default 24 hour window with owner and reviewer" do
    @ship.update_columns(reviewer_id: @reviewer.id)

    old_ship = Certification::Ship.create!(project: Project.create!(title: "old"))
    old_ship.update_columns(created_at: 3.days.ago, updated_at: 3.days.ago)

    fetch_ships
    assert_response :success

    body = response.parsed_body
    assert_equal 1, body["count"]
    ship = body["ships"].first
    assert_equal @ship.id, ship["id"]
    assert_equal "pending", ship["status"]
    assert_equal @owner.slack_id, ship.dig("owner", "slack_id")
    assert_equal @reviewer.slack_id, ship.dig("reviewer", "slack_id")
  end

  test "filters by status" do
    approved = Certification::Ship.create!(project: Project.create!(title: "done"))
    approved.update_columns(status: 1)

    fetch_ships(params: { status: "approved" })
    assert_response :success
    assert_equal [ approved.id ], response.parsed_body["ships"].map { |s| s["id"] }
  end

  test "respects an explicit since/until window" do
    @ship.update_columns(created_at: 10.days.ago, updated_at: 10.days.ago)

    fetch_ships(params: { since: 11.days.ago.iso8601, until: 9.days.ago.iso8601 })
    assert_response :success
    assert_equal [ @ship.id ], response.parsed_body["ships"].map { |s| s["id"] }
  end

  test "excludes ships of soft-deleted projects" do
    @project.update_columns(deleted_at: Time.current)

    fetch_ships
    assert_response :success
    assert_equal 0, response.parsed_body["count"]
  end

  test "rejects invalid time params" do
    fetch_ships(params: { since: "banana" })
    assert_response :bad_request

    fetch_ships(params: { hours: "0" })
    assert_response :bad_request

    fetch_ships(params: { since: 1.hour.ago.iso8601, until: 2.hours.ago.iso8601 })
    assert_response :bad_request
  end

  teardown do
    credentials_options.delete(:certification_shipwrights)
  end

  private

  # Credentials are read through a memoized options hash; mutating it is the
  # only way to inject test keys, since EncryptedConfiguration's method_missing
  # swallows minitest's Object#stub as a credential lookup.
  def credentials_options
    Rails.application.credentials.send(:options)
  end

  def fetch_ships(key: API_KEY, params: {})
    headers = key ? { "Authorization" => "Bearer #{key}" } : {}
    get api_v1_certification_ships_path, params: params, headers: headers
  end
end
