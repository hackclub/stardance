require "test_helper"

class FabricateServiceTest < ActiveSupport::TestCase
  SECRET = "fabricate-test-secret".freeze

  setup do
    @owner = create_user(slack_id: "U_FAB_SVC", display_name: "fab-svc")
    @owner.update!(bio: "I build keyboards")
    @teammate = create_user(slack_id: "U_FAB_SVC_MATE", display_name: "fab-svc-mate")
    @project = Project.create!(title: "Split keyboard", description: "Wireless", repo_url: "https://github.com/ada/split")
    @project.memberships.create!(user: @owner, role: :owner)
    @project.memberships.create!(user: @teammate, role: :contributor)
    @project.update!(hardware_stage: "design")
    @own_devlog = add_devlog(@owner, "Routed the PCB")
    add_devlog(@teammate, "Teammate's log")
  end

  test "posts the project, its owner and only the owner's devlogs, signed with the shared secret" do
    sent = nil
    result = with_fabricate(->(env) { sent = env; [ 200, { "Content-Type" => "application/json" }, { project_id: 77 }.to_json ] }) do
      FabricateService.import_project!(@project, owner: @owner, host: "https://stardance.test")
    end

    assert_equal 77, result
    assert_equal "/imports/stardance", sent.url.path
    timestamp = sent.request_headers["X-Stardance-Timestamp"]
    assert_equal "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{timestamp}.#{sent.request_body}")}", sent.request_headers["X-Stardance-Signature"]

    payload = JSON.parse(sent.request_body)
    assert_equal({ "id" => @project.id, "title" => "Split keyboard", "description" => "Wireless", "repo_url" => "https://github.com/ada/split", "demo_url" => nil, "banner_url" => nil, "created_at" => @project.created_at.iso8601 }, payload["project"])
    assert_equal({ "hca_id" => "hca-U_FAB_SVC", "email" => "fab-svc@example.test", "display_name" => "fab-svc", "bio" => "I build keyboards" }, payload["owner"])
    assert_equal [ { "id" => @own_devlog.id, "body" => "Routed the PCB", "duration_seconds" => 3600, "created_at" => @own_devlog.created_at.iso8601, "media_urls" => [] } ], payload["devlogs"]
  end

  test "a refusal from Fabricate raises" do
    error = assert_raises(FabricateService::Error) do
      with_fabricate(->(_env) { [ 422, {}, { error: "Validation failed" }.to_json ] }) do
        FabricateService.import_project!(@project, owner: @owner, host: "https://stardance.test")
      end
    end

    assert_match "422", error.message
  end

  test "nothing is sent without the shared secret" do
    FabricateService.stub(:import_secret, "") do
      assert_raises(FabricateService::Error) { FabricateService.import_project!(@project, owner: @owner, host: "https://stardance.test") }
    end
  end

  private

  def with_fabricate(handler, &block)
    stubs = Faraday::Adapter::Test::Stubs.new { |stub| stub.post("/imports/stardance") { |env| handler.call(env) } }
    connection = Faraday.new(url: FabricateService::API_URL) { |conn| conn.adapter :test, stubs }
    FabricateService.stub(:import_secret, SECRET) { FabricateService.stub(:connection, connection, &block) }
  end

  def add_devlog(user, body)
    devlog = Post::Devlog.new(body: body, duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: user, postable: devlog)
    devlog
  end
end
