require "test_helper"

module Api
  module V1
    module Missions
      # Projects attached to a mission (Api::V1::Missions::ProjectsController).
      class ProjectsTest < ActionDispatch::IntegrationTest
        include ApiRequestHelpers

        setup do
          @user    = users(:one)
          @mission = Mission.create!(slug: "test-mission", name: "Test Mission",
                                     description: "A mission for tests")
          @mission.attachments.create!(project: projects(:one))
          @url = api_v1_mission_projects_url(@mission.slug)
        end

        test "requires authentication" do
          get @url

          assert_response :unauthorized
        end

        test "lists active attached projects with pagination" do
          get @url, headers: api_headers(@user)

          assert_response :success
          ids = json_response["projects"].map { |p| p["id"] }
          assert_includes ids, projects(:one).id
          assert json_response["pagination"].present?
        end

        test "excludes detached projects" do
          @mission.attachments.create!(project: projects(:two), detached_at: Time.current)

          get @url, headers: api_headers(@user)

          ids = json_response["projects"].map { |p| p["id"] }
          assert_includes ids, projects(:one).id
          assert_not_includes ids, projects(:two).id
        end

        test "unknown mission slug returns 404" do
          get api_v1_mission_projects_url("does-not-exist"), headers: api_headers(@user)

          assert_response :not_found
        end

        test "disabled mission is not found" do
          @mission.update!(enabled: false)

          get @url, headers: api_headers(@user)

          assert_response :not_found
        end
      end
    end
  end
end
