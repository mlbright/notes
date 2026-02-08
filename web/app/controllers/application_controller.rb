class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :check_session_timeout

  private

  def set_note
    @note = current_user.accessible_notes.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to notes_path, alert: "Note not found." }
      format.json { render json: { error: "Note not found" }, status: :not_found }
    end
  end
end
