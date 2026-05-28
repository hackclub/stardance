module Admin
  module Missions
    class GuidePastesController < BaseController
      MAX_PASTE_BYTES = 200_000

      def create
        language_label = params[:language].to_s.strip
        body = params[:body].to_s

        if language_label.blank?
          redirect_to edit_admin_mission_path(@mission.slug),
                      alert: "Pick a language name first." and return
        end

        if body.bytesize > MAX_PASTE_BYTES
          redirect_to edit_admin_mission_path(@mission.slug, language: language_label),
                      alert: "Guide is too large (#{(body.bytesize / 1024.0).round}KB). Max is #{MAX_PASTE_BYTES / 1024}KB." and return
        end

        if Mission.guide_paste_preamble(body).present?
          redirect_to edit_admin_mission_path(@mission.slug, language: language_label),
                      alert: "Move any intro text inside the first step — the guide must start with an `## H2 heading`." and return
        end

        # Case-insensitive match — re-pasting `python` finds the existing `Python`
        # variant instead of tripping uniqueness.
        variant = @mission.guide_variants
                          .where("LOWER(language) = ?", language_label.downcase)
                          .first ||
                  @mission.guide_variants.new(
                    language: language_label,
                    position: (@mission.guide_variants.maximum(:position).to_i + 1)
                  )
        variant.body = body
        variant.save!

        redirect_to edit_admin_mission_path(@mission.slug, language: variant.language),
                    notice: "Guide replaced for #{variant.language}."
      end
    end
  end
end
