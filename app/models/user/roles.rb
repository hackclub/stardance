module User::Roles
  extend ActiveSupport::Concern

  included do
    User::Role.all_slugs.each do |role_name|
      define_method "#{role_name}?" do
        has_role?(role_name)
      end
    end
  end

  def roles = granted_roles&.map(&:to_sym) || []

  def has_role?(role_name) = roles.include?(role_name.to_sym)

  def admin? = has_role?(:admin) || has_role?(:super_admin)

  def can_review? = admin? || has_role?(:project_certifier)

  def can_nominate_super_star? = can_review? || has_role?(:guardian_of_integrity)

  def can_see_deleted_devlogs? = admin? || has_role?(:fraud_dept)

  def highest_role
    roles.min_by { |role| User::Role.all_slugs.index(role) }&.to_s&.titleize || "User"
  end

  def grant_role!(role_name)
    role = role_name.to_sym
    raise ArgumentError, "Invalid role: #{role_name}" unless User::Role.all_slugs.include?(role)

    return if has_role?(role)

    update!(granted_roles: roles + [ role ])
    notify_role_granted(role)
  end

  def remove_role!(role_name)
    role = role_name.to_sym
    raise ArgumentError, "Invalid role: #{role_name}" unless User::Role.all_slugs.include?(role)

    update!(granted_roles: roles - [ role ]) if has_role?(role)
  end

  private

    def notify_role_granted(role)
      return if Rails.env.development?
      return unless slack_id.present?

      role_info = User::Role.find(role)
      message = "Congratulations! You've been granted the *#{role_info.name.to_s.titleize}* role on Stardance."
      dm_user(message)
    end
end
