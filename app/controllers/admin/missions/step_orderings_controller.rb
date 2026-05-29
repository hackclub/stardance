module Admin
  module Missions
    class StepOrderingsController < BaseController
      def create
        ids = Array(params[:order]).map(&:to_i)
        return head :unprocessable_entity if ids.empty?

        steps_by_id = @mission.steps.where(deleted_at: nil, id: ids).index_by(&:id)

        Mission::Step.transaction do
          ids.each_with_index do |id, idx|
            step = steps_by_id[id]
            next unless step
            # .update! (not update_all) so PaperTrail records who reshuffled steps.
            step.update!(position: idx + 1) if step.position != idx + 1
          end
        end

        @mission.guide_variants.find_each do |v|
          @mission.regenerate_text_for_language!(v.language)
        end

        head :ok
      end
    end
  end
end
