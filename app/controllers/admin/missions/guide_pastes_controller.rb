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

        body = strip_preamble(body)

        if Mission.parse_h2_sections(body).empty?
          redirect_to edit_admin_mission_path(@mission.slug, language: language_label),
                      alert: "No steps found — the guide needs at least one ## heading." and return
        end

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

      private

      def strip_preamble(text)
        normalized = text.gsub("\r\n", "\n").gsub("\r", "\n")
        lines = normalized.split("\n")

        # If there are no ## headings but there are # headings, promote them.
        has_h2 = lines.any? { |l| l.match?(/\A##\s+/) }
        unless has_h2
          has_h1 = lines.any? { |l| l.match?(/\A#\s+/) }
          lines = lines.map { |l| l.sub(/\A#(\s+)/, '##\1') } if has_h1
        end

        first_h2 = lines.index { |l| l.match?(/\A##\s+/) }
        return lines.join("\n") if first_h2.nil? || first_h2 == 0
        lines.drop(first_h2).join("\n")
      end
    end
  end
end
