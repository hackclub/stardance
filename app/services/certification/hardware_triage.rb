# frozen_string_literal: true

# Advisory SDHWEX findings, not live checks or review decisions. The snapshot is
# bundled now that submissions are closed; changes go through code review.
# Source: https://sdhwex-data.enderium42.workers.dev/v1/triage.json (2026-11-10).
# The original check dates are preserved, not advanced to the import date.
class Certification::HardwareTriage
  DATA = JSON.parse(Rails.root.join("config/hardware_triage.json").read, freeze: true)
  PROJECTS = %w[design build].to_h do |stage|
    [ stage, DATA.fetch(stage).fetch("projects").index_by { |project| project.fetch("project_id") }.freeze ]
  end.freeze

  attr_reader :stage, :snapshot, :project

  def initialize(review_type:, project_id:)
    @stage = { funding: "design", ship: "build" }[review_type]
    @snapshot = DATA.fetch(stage) if stage
    @project = PROJECTS.fetch(stage)[project_id.to_s] if stage
  end

  def self.guidelines
    DATA.fetch("guidelines")
  end

  def feedback
    return unless project && project.fetch("fail").any?

    "Hey! Your project \"#{project.fetch('title')}\" isn't ready for #{stage} approval yet. Here's what's missing based on the shipping checklist:\n" +
      project.fetch("fail").map { |finding| "- #{finding}" }.join("\n") +
      "\n\n#{self.class.guidelines}"
  end

  def safe_link(value)
    uri = URI.parse(value.to_s)
    uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end
end
