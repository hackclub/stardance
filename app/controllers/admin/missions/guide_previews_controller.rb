module Admin
  module Missions
    class GuidePreviewsController < BaseController
      MAX_PREVIEW_BYTES = 100_000

      def create
        return head :payload_too_large if params[:markdown].to_s.bytesize > MAX_PREVIEW_BYTES
        preview_mission = Mission.new(submission_guide: params[:markdown].to_s)
        render partial: "missions/submission_requirements", locals: { mission: preview_mission }
      end
    end
  end
end
