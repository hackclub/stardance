class AdminConstraint
  def self.matches?(request)
    # otherwise admins who impersonated non admins can't stop
    if request.path == "/admin/impersonation" && request.request_method == "DELETE" && request.session[:impersonator_user_id].present?
      user = User.find_by(id: request.session[:impersonator_user_id])
    else
      user = admin_user_for(request)
    end

    return false unless user

    policy = AdminPolicy.new(user, :admin)
    policy.access_admin_endpoints? ||
      policy.access_fulfillment_view? ||
      policy.access_ship_review? ||
      policy.access_ysws_review? ||
      policy.access_raffles?
  end

  def self.admin_user_for(request)
    user = User.find_by(id: request.session[:user_id])
    return user if user

    if Rails.env.development? && ENV["DEV_ADMIN_USER_ID"].present?
      User.find_by(id: ENV["DEV_ADMIN_USER_ID"])
    end
  end

  def self.allow?(request, permission)
    user = admin_user_for(request)
    user && AdminPolicy.new(user, :admin).public_send(permission)
  end
end
