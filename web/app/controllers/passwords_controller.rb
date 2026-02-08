class PasswordsController < ApplicationController
  before_action :require_login

  def edit
  end

  def update
    if current_user.password_digest.present? && !current_user.authenticate(params[:current_password])
      flash.now[:alert] = "Current password is incorrect."
      render :edit, status: :unprocessable_entity
      return
    end

    if current_user.update(password_params)
      redirect_to notes_path, notice: "Password updated successfully."
    else
      flash.now[:alert] = current_user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def password_params
    params.permit(:password, :password_confirmation)
  end
end
