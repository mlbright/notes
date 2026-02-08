class NoteVersionsController < ApplicationController
  before_action :require_login
  before_action :set_note
  before_action :set_version, only: [ :show, :restore ]

  def index
    @versions = @note.note_versions.ordered
  end

  def show
  end

  def restore
    @note.update!(title: @version.title, body: @version.body)
    redirect_to @note, notice: "Note restored to version #{@version.version_number}."
  end

  private

  def set_note
    @note = current_user.accessible_notes.find(params[:note_id])
  end

  def set_version
    @version = @note.note_versions.find(params[:id])
  end
end
