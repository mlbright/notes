class SharesController < ApplicationController
  before_action :require_login
  before_action :set_note
  before_action :require_ownership

  def create
    user = User.find_by(email: params[:email])
    unless user
      redirect_to @note, alert: "User not found."
      return
    end

    @share = @note.shares.build(user: user, permission: :read_write)

    if @share.save
      redirect_to @note, notice: "Note shared with #{user.name}."
    else
      redirect_to @note, alert: @share.errors.full_messages.join(", ")
    end
  end

  def destroy
    share = @note.shares.find(params[:id])
    share.destroy!
    redirect_to @note, notice: "Share revoked."
  end

  private

  def set_note
    @note = current_user.notes.find(params[:note_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to notes_path, alert: "Note not found."
  end

  def require_ownership
    unless @note.user == current_user
      redirect_to notes_path, alert: "Only the owner can manage sharing."
    end
  end
end
