module ProjectsHelper
  def safe(url, text = nil)
    return unless url.present? && url.start_with?("http")
    link_to(text || url, url, target: "_blank")
  end

  # Every pill a hardware project shows beside its title, in render order.
  # Kept as one declarative list so adding a pill is a single row rather than
  # another branch in the view:
  #
  #   (project_pill("Design Returned", :returned, members_only: true) if ...),
  #
  # `privileged` should be true for project members and admins; pills built
  # with `members_only: true` are dropped for everyone else. A modifier that
  # isn't already in _show.scss needs a rule adding there for its colour.
  def hardware_pills(project, privileged:)
    tier = project.complexity_tier

    pills = [
      project_pill("Hardware", :hardware),
      (project_pill(tier[:name], :tier, :"tier-#{tier[:code].downcase}") if tier),
      project_pill(project.design_stage? ? "Design Stage" : "Build Stage", :stage),
      (project_pill("Design Approved", :approved) if project.received_grant?),
      (project_pill("Build Approved", :approved) if project.build_approved?)
    ].compact

    privileged ? pills : pills.reject { |pill| pill[:members_only] }
  end

  # One pill. `modifiers` are .project-show__tag--<modifier> suffixes; see
  # pages/projects/_show.scss for the colour each one carries.
  def project_pill(label, *modifiers, members_only: false)
    {
      label: label,
      css_class: class_names("project-show__tag", modifiers.map { |modifier| "project-show__tag--#{modifier}" }),
      members_only: members_only
    }
  end
end
