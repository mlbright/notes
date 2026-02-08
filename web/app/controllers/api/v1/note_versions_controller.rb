module Api
  module V1
    class NoteVersionsController < Api::BaseController
      before_action :set_note

      def index
        versions = @note.note_versions.ordered
        render json: versions
      end

      def show
        version = @note.note_versions.find(params[:id])
        render json: version.as_json(methods: [ :diff_from_current ])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Version not found" }, status: :not_found
      end

      def restore
        version = @note.note_versions.find(params[:id])
        @note.update!(title: version.title, body: version.body)
        render json: note_json(@note)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Version not found" }, status: :not_found
      end

      private

      def set_note
        @note = current_user.accessible_notes.find(params[:note_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Note not found" }, status: :not_found
      end

      def note_json(note)
        note.as_json(include: { tags: { only: [ :id, :name, :color ] } })
      end
    end
  end
end
