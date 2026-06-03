module Admin
  module Missions
    class LanguageRenamesController < BaseController
      def create
        old_name = params[:old_language].to_s.strip
        new_name = params[:new_language].to_s.strip

        if old_name.blank? || new_name.blank?
          redirect_to edit_admin_mission_path(@mission.slug, language: old_name),
                      alert: "Language name can't be blank." and return
        end

        if old_name.downcase == new_name.downcase
          redirect_to edit_admin_mission_path(@mission.slug, language: new_name) and return
        end

        variant = @mission.guide_variants.find_by("LOWER(language) = ?", old_name.downcase)
        unless variant
          redirect_to edit_admin_mission_path(@mission.slug),
                      alert: "Language "# {old_name}" not found." and return
        end

        existing = @mission.guide_variants.find_by("LOWER(language) = ?", new_name.downcase)
        if existing
          redirect_to edit_admin_mission_path(@mission.slug, language: existing.language),
                      alert: "A guide for "# {existing.language}" already exists." and return
        end

        Mission::GuideVariant.transaction do
          variant.update!(language: new_name)

          Mission::StepBody
            .where(mission_step_id: @mission.steps.select(:id))
            .where("LOWER(language) = ?", old_name.downcase)
            .update_all(language: new_name)
        end

        redirect_to edit_admin_mission_path(@mission.slug, language: new_name),
                    notice: "Language renamed from "# {old_name}" to "#{new_name}"."
      end

      def destroy
        language = params[:language].to_s.strip

        if language.blank?
          redirect_to edit_admin_mission_path(@mission.slug),
                      alert: "No language specified." and return
        end

        variant = @mission.guide_variants.find_by("LOWER(language) = ?", language.downcase)
        unless variant
          redirect_to edit_admin_mission_path(@mission.slug),
                      alert: "Language "# {language}" not found." and return
        end

        Mission::GuideVariant.transaction do
          Mission::StepBody
            .where(mission_step_id: @mission.steps.select(:id))
            .where("LOWER(language) = ?", language.downcase)
            .delete_all

          variant.destroy!
        end

        fallback = @mission.default_guide&.language
        redirect_to edit_admin_mission_path(@mission.slug, language: fallback),
                    notice: "Language "# {language}" deleted."
      end
    end
  end
end
