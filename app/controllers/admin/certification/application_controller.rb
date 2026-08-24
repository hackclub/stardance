class Admin::Certification::ApplicationController < Admin::ApplicationController
  # The hardware review views (queue + show) reference these path helpers. The
  # global dash and the funding/ship verdict controllers use the global routes;
  # the per-mission dash overrides them (see Admin::Missions::HardwareReviews).
  helper_method :hardware_review_path, :hardware_queue_path, :hardware_next_path,
                :hardware_queue_title, :hardware_back_link, :hardware_flag_for_fraud_path

  private

  def hardware_review_path(project)
    admin_certification_hardware_review_path(project)
  end

  def hardware_flag_for_fraud_path(project)
    flag_for_fraud_admin_certification_hardware_review_path(project)
  end

  def hardware_queue_path(stage)
    stage.to_s == "build" ? build_admin_certification_hardware_reviews_path : design_admin_certification_hardware_reviews_path
  end

  def hardware_next_path(stage:, skip: nil)
    next_admin_certification_hardware_reviews_path(stage: stage, skip: skip)
  end

  def hardware_queue_title(design)
    "#{design ? 'Design' : 'Build'} review queue"
  end

  def hardware_back_link
    { label: "← back to admin", path: admin_root_path }
  end

  # Hardware review lives in two places: the global dash for non-mission
  # hardware, and a per-mission dash for hardware-mission projects. Verdicts and
  # claims return the reviewer to whichever one the project belongs to.
  def hardware_review_path_for(project)
    mission = project.current_mission
    if mission&.hardware?
      admin_mission_hardware_review_path(mission.slug, project)
    else
      admin_certification_hardware_review_path(project)
    end
  end

  def hardware_review_next_path_for(project, stage)
    mission = project.current_mission
    if mission&.hardware?
      next_admin_mission_hardware_reviews_path(mission.slug, stage: stage)
    else
      next_admin_certification_hardware_reviews_path(stage: stage)
    end
  end
end
