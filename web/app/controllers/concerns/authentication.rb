module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :logged_in?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    unless logged_in?
      respond_to do |format|
        format.html { redirect_to login_path, alert: "Please sign in to continue." }
        format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
      end
    end
  end

  def require_admin
    require_login
    return if performed?
    unless current_user.admin?
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Access denied." }
        format.json { render json: { error: "Forbidden" }, status: :forbidden }
      end
    end
  end

  def check_session_timeout
    return unless logged_in?
    if session[:last_seen_at] && session[:last_seen_at] < current_user.session_timeout.seconds.ago
      reset_session
      redirect_to login_path, alert: "Session expired. Please sign in again."
    else
      session[:last_seen_at] = Time.current
    end
  end
end
