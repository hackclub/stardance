class Admin::UsersController < Admin::ApplicationController
  def index
    authorize User
    @query = params[:query]

    users = User.all
    if @query.present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      users = users.where("email ILIKE ? OR display_name ILIKE ? OR slack_id ILIKE ?", q, q, q)
    end

    @pagy, @users = pagy(:offset, users.order(:id))
  end

  def show
    if params[:id].starts_with?("@")
      @user = User.find_by!("LOWER(display_name) = ?", params[:id][1..].downcase)
    else
      @user = User.includes(:identities).find(params[:id])
    end

    authorize @user

    @all_projects = @user.projects.with_deleted.order(deleted_at: :desc)
  end

  def update
    if params[:id].starts_with?("@")
      @user = User.find_by!("LOWER(display_name) = ?", params[:id][1..].downcase)
    else
      @user = User.find(params[:id])
    end

    authorize @user

    old_regions = @user.regions.dup

    if params[:user][:regions].present?
      params[:user][:regions] = params[:user][:regions].reject(&:blank?)
    end

    if @user.update(user_params)
      if old_regions != @user.regions
        ::PaperTrail::Version.create!(
          item_type: "User",
          item_id: @user.id,
          event: "regions_updated",
          whodunnit: current_user.id.to_s,
          object_changes: { regions: [ old_regions, @user.regions ] }.to_json
        )
      end
      flash[:notice] = "User updated successfully."
    else
      flash[:alert] = "Failed to update user."
    end

    redirect_to admin_user_path(@user)
  end

  def user_perms
    authorize User, :index?
    @users = User.where("array_length(granted_roles, 1) > 0").order(:id)
  end

  private

  def user_params
    params.require(:user).permit(:internal_notes, regions: [])
  end
end
