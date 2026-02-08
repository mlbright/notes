class AdminController < ApplicationController
  before_action :require_admin

  def dashboard
    @users = User.all.order(:name)
    @total_notes = Note.count
    @total_users = User.count
  end

  def update_user
    @user = User.find(params[:id])
    if @user.update(admin_user_params)
      redirect_to admin_dashboard_path, notice: "User updated."
    else
      redirect_to admin_dashboard_path, alert: @user.errors.full_messages.join(", ")
    end
  end

  def destroy_user
    @user = User.find(params[:id])
    if @user == current_user
      redirect_to admin_dashboard_path, alert: "You cannot delete yourself."
    else
      @user.destroy!
      redirect_to admin_dashboard_path, notice: "User deleted."
    end
  end

  private

  def admin_user_params
    params.require(:user).permit(:role, :session_timeout)
  end
end
