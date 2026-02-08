class SessionsController < ApplicationController
  skip_before_action :check_session_timeout, only: [ :new, :create, :create_from_password, :destroy ]

  def new
    redirect_to notes_path if logged_in?
  end

  def create
    auth = request.env["omniauth.auth"]
    user = User.from_omniauth(auth)
    start_session(user)
    redirect_to notes_path, notice: "Signed in successfully."
  end

  def create_from_password
    user = User.authenticate_by_password(params[:email], params[:password])
    if user
      start_session(user)
      redirect_to notes_path, notice: "Signed in successfully."
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end

  def failure
    redirect_to login_path, alert: "Authentication failed: #{params[:message]}"
  end

  private

  def start_session(user)
    session[:user_id] = user.id
    session[:last_seen_at] = Time.current
  end
end
