class SessionTimeoutsController < ApplicationController
  before_action :require_login

  SESSION_TIMEOUT_OPTIONS = [
    { label: "1 hour", value: 3600 },
    { label: "8 hours", value: 28_800 },
    { label: "1 day", value: 86_400 },
    { label: "7 days", value: 604_800 },
    { label: "30 days", value: 2_592_000 }
  ].freeze

  def edit
    @timeout_options = SESSION_TIMEOUT_OPTIONS
    @current_timeout = current_user.session_timeout
  end

  def update
    timeout = params[:session_timeout].to_i

    if current_user.update(session_timeout: timeout)
      redirect_to notes_path, notice: "Session timeout updated."
    else
      @timeout_options = SESSION_TIMEOUT_OPTIONS
      @current_timeout = current_user.session_timeout
      flash.now[:alert] = current_user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
