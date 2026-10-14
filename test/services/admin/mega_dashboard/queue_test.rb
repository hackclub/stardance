require "test_helper"

module Admin
  module MegaDashboard
    class QueueTest < ActiveSupport::TestCase
      setup do
        Flipper.enable(:hardware_flow)
        # Funding requests require a verified, YSWS-eligible owner.
        @owner = ::User.create!(
          slack_id: "U_QUEUE_OWNER", display_name: "queue-owner", email: "queue-owner@example.test",
          verification_status: :verified, ysws_eligible: true
        )
        @mission = ::Mission.create!(
          slug: "hw-queue-#{SecureRandom.hex(3)}", name: "Hardware mission",
          description: "Build something", hardware: true
        )
      end

      teardown { Flipper.disable(:hardware_flow) }

      test "the hardware design queue counts only what its dash can hand out" do
        reviewable = funding_request(hardware_project("design"))
        deleted = funding_request(hardware_project("design"))
        deleted.project.soft_delete!
        on_mission = funding_request(attach_to_mission(hardware_project("design")))

        pending = Queue.find("hardware_design").pending.call

        assert_includes pending, reviewable
        assert_not_includes pending, deleted
        assert_not_includes pending, on_mission
      end

      test "the hardware build queue counts only what its dash can hand out" do
        reviewable = ship(hardware_project("build"))
        deleted = ship(hardware_project("build"))
        deleted.project.soft_delete!
        on_mission = ship(attach_to_mission(hardware_project("build")))

        pending = Queue.find("hardware_build").pending.call

        assert_includes pending, reviewable
        assert_not_includes pending, deleted
        assert_not_includes pending, on_mission
      end

      test "hardware build certifications stay out of the software ship queue" do
        hardware = ship(hardware_project("build"))

        assert_not_includes Queue.find("ship_certifications").pending.call, hardware
      end

      test "the software mission queue leaves out submissions still awaiting certification" do
        mission = create_mission
        queued = ship_to_mission!(software_project, @owner, mission, status: "pending")
        not_yet = ship_to_mission!(software_project, @owner, mission)

        pending = Queue.find("mission_reviews_software").pending.call

        assert_equal "awaiting_certification", not_yet.status
        assert_includes pending, queued
        assert_not_includes pending, not_yet
      end

      test "the software mission queue splits on the mission flag, not the project" do
        on_hardware_mission = ship_to_mission!(software_project, @owner, @mission, status: "pending")
        hardware_build = ship_to_mission!(hardware_project("build"), @owner, create_mission, status: "pending")

        pending = Queue.find("mission_reviews_software").pending.call

        assert_not_includes pending, on_hardware_mission
        assert_includes pending, hardware_build
      end

      test "the hardware mission queue counts the funding and ship reviews its dash hands out" do
        on_mission = attach_to_mission(hardware_project("design"))
        funding_request(on_mission)
        ship(on_mission)
        funding_request(hardware_project("design"))
        deleted = attach_to_mission(hardware_project("design"))
        funding_request(deleted)
        deleted.soft_delete!

        assert_equal 2, Queue.find("mission_reviews_hardware").open_entered_ats.size
      end

      test "a rerouted review counts like an unsubmitted one, not a decision" do
        project = hardware_project("build")
        cert = ship(project)
        pairs = -> { Queue.find("hardware_build").timestamp_pairs(3.days.ago) }

        assert_equal 1, pairs.call.size

        cert.update!(status: :misfiled)
        assert_empty pairs.call, "a misfiled review should leave the queue entirely"

        cert.update!(status: :withdrawn)
        assert_empty pairs.call, "a withdrawn review should leave the queue entirely"
      end

      private

      def software_project
        project = ::Project.create!(title: "SW #{SecureRandom.hex(4)}")
        project.memberships.create!(user: @owner, role: :owner)
        project
      end

      def hardware_project(stage)
        project = ::Project.create!(title: "HW #{SecureRandom.hex(4)}")
        project.memberships.create!(user: @owner, role: :owner)
        project.update!(hardware_stage: stage)
        project
      end

      # Attached before the review is created: attaching a shipped project to a
      # mission is rejected.
      def attach_to_mission(project)
        ::Project::MissionAttachment.create!(project: project, mission: @mission)
        project
      end

      def funding_request(project)
        add_devlog(project)
        project.certification_funding_requests.create!(
          user: @owner, complexity_tier: 2, requested_amount_cents: 4_200, status: :pending
        )
      end

      def ship(project)
        ::Certification::Ship.create!(project: project, status: :pending)
      end

      def add_devlog(project)
        devlog = ::Post::Devlog.new(body: "initial log", duration_seconds: 3600, phase: project.hardware_stage)
        devlog.uploading_attachments = true
        devlog.save!
        ::Post.create!(project: project, user: @owner, postable: devlog)
      end
    end
  end
end
