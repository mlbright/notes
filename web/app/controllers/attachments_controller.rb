class AttachmentsController < ApplicationController
  before_action :require_login

  MAX_FILE_SIZE = 25.megabytes

  def create
    @note = current_user.accessible_notes.find(params[:note_id])
    unless @note.editable_by?(current_user)
      redirect_to @note, alert: "You don't have permission to add attachments."
      return
    end

    files = params[:files]
    if files.blank?
      redirect_to @note, alert: "No files selected."
      return
    end

    oversized = files.select { |f| f.size > MAX_FILE_SIZE }
    if oversized.any?
      redirect_to @note, alert: "Files must be under 25 MB each."
      return
    end

    @note.attachments.attach(files)
    redirect_to @note, notice: "#{files.size} file(s) attached."
  end

  def destroy
    @note = current_user.accessible_notes.find(params[:note_id])
    unless @note.editable_by?(current_user)
      redirect_to @note, alert: "You don't have permission to remove attachments."
      return
    end

    attachment = @note.attachments.find(params[:id])
    attachment.purge
    redirect_to @note, notice: "Attachment removed."
  end
end
