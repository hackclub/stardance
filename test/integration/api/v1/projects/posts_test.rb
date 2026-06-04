require "test_helper"

module Api
  module V1
    module Projects
      class PostsTest < ActionDispatch::IntegrationTest
        include ApiRequestHelpers

        setup do
          @member   = users(:one)  # creator on project one (memberships(:one))
          @outsider = users(:two)  # not a member of project one
          @project  = projects(:one)

          # uploading_attachments skips the "at least one image/video" presence
          # check, so we don't need to fake-attach a (spoofing-protected) blob.
          @devlog = Post::Devlog.new(body: "original body", duration_seconds: 3600)
          @devlog.uploading_attachments = true
          @devlog.save!
          @post = Post.create!(project: @project, user: @member, postable: @devlog)
        end

        # --- create -------------------------------------------------------

        test "create requires authentication" do
          post api_v1_project_posts_url(@project), params: { body: "hi" }

          assert_response :unauthorized
        end

        test "create is forbidden for non-members" do
          assert_no_difference -> { @project.posts.count } do
            post api_v1_project_posts_url(@project),
                 params: { body: "hi" }, headers: api_headers(@outsider)
          end

          assert_response :forbidden
        end

        test "create requires the project to have a linked Hackatime project" do
          assert_empty @project.hackatime_keys, "fixture project should have no hackatime keys"

          assert_no_difference -> { @project.posts.count } do
            post api_v1_project_posts_url(@project),
                 params: { body: "hi" }, headers: api_headers(@member)
          end

          assert_response :unprocessable_entity
          assert_match(/Hackatime/, json_response["error"])
        end

        # --- update -------------------------------------------------------

        test "owner can update their devlog and receives the post back" do
          patch api_v1_project_post_url(@project, @post),
                params: { body: "edited body" }, headers: api_headers(@member)

          assert_response :success
          assert_equal "edited body", @devlog.reload.body
          assert_equal @post.id, json_response["id"]
        end

        test "update is forbidden for non-owners" do
          patch api_v1_project_post_url(@project, @post),
                params: { body: "hax" }, headers: api_headers(@outsider)

          assert_response :forbidden
          assert_equal "original body", @devlog.reload.body
        end

        test "only devlog posts can be updated" do
          ship_post = build_ship_post

          patch api_v1_project_post_url(@project, ship_post),
                params: { body: "edited" }, headers: api_headers(@member)

          assert_response :forbidden
          assert_match(/devlog/i, json_response["error"])
        end

        # --- destroy ------------------------------------------------------

        test "owner can soft-delete their devlog" do
          delete api_v1_project_post_url(@project, @post), headers: api_headers(@member)

          assert_response :no_content
          assert @devlog.reload.deleted_at.present?
        end

        test "destroy is forbidden for non-owners" do
          delete api_v1_project_post_url(@project, @post), headers: api_headers(@outsider)

          assert_response :forbidden
          assert_nil @devlog.reload.deleted_at
        end

        test "only devlog posts can be deleted" do
          ship_post = build_ship_post

          delete api_v1_project_post_url(@project, ship_post), headers: api_headers(@member)

          assert_response :forbidden
        end

        test "cannot delete a devlog from a shipped project" do
          @project.update_columns(shipped_at: Time.current)

          delete api_v1_project_post_url(@project, @post), headers: api_headers(@member)

          assert_response :unprocessable_entity
          assert_match(/shipped/i, json_response["error"])
          assert_nil @devlog.reload.deleted_at
        end

        private

        # A ship-event post by @member on @project. ShipEvent also requires an
        # attachment on create, so skip that check the same way as the devlog.
        def build_ship_post
          ship = Post::ShipEvent.new(body: "shipped")
          ship.uploading_attachments = true
          ship.save!
          Post.create!(project: @project, user: @member, postable: ship)
        end
      end
    end
  end
end
