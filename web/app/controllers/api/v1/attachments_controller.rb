module Api
  module V1
    class AttachmentsController < Api::BaseController
      MAX_FILE_SIZE = 25.megabytes

      before_action :set_note

      def index
        attachments = @note.attachments.map do |attachment|
          {
            id: attachment.id,
            filename: attachment.filename.to_s,
            content_type: attachment.content_type,
            byte_size: attachment.byte_size,
            created_at: attachment.created_at
          }
        end
        render json: attachments
      end

      def create
        unless @note.editable_by?(current_user)
          render json: { error: "Permission denied" }, status: :forbidden
          return
        end

        files = params[:files]
        if files.blank?
          render json: { error: "No files provided" }, status: :bad_request
          return
        end

        oversized = files.select { |f| f.size > MAX_FILE_SIZE }
        if oversized.any?
          render json: { error: "Files must be under 25 MB each" }, status: :unprocessable_entity
          return
        end

        @note.attachments.attach(files)
        render json: { message: "#{files.size} file(s) attached" }, status: :created
      end

      def destroy
        unless @note.editable_by?(current_user)
          render json: { error: "Permission denied" }, status: :forbidden
          return
        end

        attachment = @note.attachments.find(params[:id])
        attachment.purge
        render json: { message: "Attachment removed" }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Attachment not found" }, status: :not_found
      end

      private

      def set_note
        @note = current_user.accessible_notes.find(params[:note_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Note not found" }, status: :not_found
      end
    end
  end
end
