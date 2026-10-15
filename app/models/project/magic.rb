class Project::Magic
  include ActiveModel::Model

  attr_reader :project

  def initialize(project)
    @project = project
  end

  # A Shipwright proposes the project for Super Star. It stays a proposal until
  # an admin grants it, so this records who nominated it and nothing more.
  def nominate(reviewer)
    return false unless ensure_open_for_nomination
    perform(reviewer, "nominate_fire") do
      project.update!(nominated_fire_at: Time.current, nominated_fire_by: reviewer)
    end
  end

  def withdraw_nomination(reviewer)
    return false unless ensure_nominated
    # Once granted, the nomination is settled — clearing it here would strip the
    # nominator while leaving the project a Super Star. Un-fire via revoke first.
    return false unless ensure_not_fire
    perform(reviewer, "withdraw_fire_nomination") do
      project.update!(nominated_fire_at: nil, nominated_fire_by: nil)
    end
  end

  def grant(user)
    return false unless ensure_not_fire
    return false unless perform(user, "mark_fire") do
      fire_event = Post::FireEvent.create!()
      project.posts.create!(user: user, postable: fire_event)
      project.update!(marked_fire_at: Time.current, marked_fire_by: user)
    end
    enqueue_magic_jobs
    if Flipper.enabled?(:week_2_release)
      project.users.each { |member| member.award_achievement!(:super_star) }
    end
    true
  end

  def revoke(user)
    return false unless ensure_fire
    perform(user, "unmark_fire") do
      project.update!(marked_fire_at: nil, marked_fire_by: nil)
    end
  end

  private

  def ensure_open_for_nomination
    if project.fire?
      errors.add(:base, "Project is already marked as Super Star.")
      return false
    end
    if project.nominated_fire_at?
      errors.add(:base, "Project has already been nominated.")
      return false
    end
    true
  end

  def ensure_nominated
    return true if project.nominated_fire_at?
    errors.add(:base, "Project hasn't been nominated.")
    false
  end

  def ensure_not_fire
    return true unless project.fire?
    errors.add(:base, "Project is already marked as Super Star.")
    false
  end

  def ensure_fire
    return true if project.fire?
    errors.add(:base, "Project is not marked as Super Star.")
    false
  end

  def perform(user, event)
    PaperTrail.request(whodunnit: user.id) do
      Project.transaction do
        project.paper_trail_event = event
        yield
      end
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.merge!(e.record.errors)
    false
  end

  def enqueue_magic_jobs
    Project::PostToMagicJob.perform_later(project)
    Project::MagicHappeningLetterJob.perform_later(project)
    project.users.find_each do |user|
      Notifications::Projects::SuperStar.notify(recipient: user, actor: project.marked_fire_by, record: project)
    end
  end
end
