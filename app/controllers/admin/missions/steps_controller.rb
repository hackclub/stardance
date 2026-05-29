module Admin
  module Missions
    class StepsController < BaseController
      before_action :resolve_language
      before_action :set_step, only: [ :update, :destroy ]

      def create
        if @language.blank?
          redirect_to edit_admin_mission_path(@mission.slug),
                      alert: "Pick a language tab first (or paste a full guide to start one)." and return
        end

        if step_params[:body].to_s.strip.blank?
          redirect_to edit_admin_mission_path(@mission.slug, language: @language),
                      alert: "Step body can't be blank — write something for the #{@language} guide." and return
        end

        step = @mission.steps.new(
          title: step_params[:title],
          position: next_position
        )
        Mission::Step.transaction do
          step.save!
          step.upsert_body_for!(@language, step_params[:body])
        end
        @mission.regenerate_text_for_language!(@language)
        redirect_to edit_admin_mission_path(@mission.slug, language: @language),
                    notice: "Step added."
      end

      def update
        if step_params[:direction].present?
          reorder!(step_params[:direction])
        else
          Mission::Step.transaction do
            @step.update!(title: step_params[:title]) if step_params[:title].present? && step_params[:title] != @step.title
            @step.upsert_body_for!(@language, step_params[:body]) if step_params.key?(:body)
          end
        end
        @mission.regenerate_text_for_language!(@language)
        redirect_to edit_admin_mission_path(@mission.slug, language: @language),
                    notice: "Step updated."
      end

      def destroy
        # Steps are shared across languages — soft-delete affects every variant.
        @step.update!(deleted_at: Time.current)
        @mission.guide_variants.find_each do |v|
          @mission.regenerate_text_for_language!(v.language)
        end
        redirect_to edit_admin_mission_path(@mission.slug, language: @language),
                    notice: "Step removed."
      end

      private

      def resolve_language
        @language = @mission.resolve_storage_language(params[:language].presence)
      end

      def set_step
        @step = @mission.steps.find(params[:id])
      end

      def step_params
        params.require(:mission_step).permit(:title, :body, :direction)
      end

      def next_position
        (@mission.steps.maximum(:position) || 0) + 1
      end

      def reorder!(direction)
        siblings = @mission.steps.ordered.to_a
        idx = siblings.index { |s| s.id == @step.id }
        return unless idx

        target_idx = direction == "up" ? idx - 1 : idx + 1
        return if target_idx < 0 || target_idx >= siblings.length

        other = siblings[target_idx]
        Mission::Step.transaction do
          mine, theirs = @step.position, other.position
          @step.update!(position: theirs)
          other.update!(position: mine)
        end
      end
    end
  end
end
