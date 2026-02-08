module Api
  module V1
    class NotesController < Api::BaseController
      before_action :set_note, only: [ :show, :update, :destroy, :restore, :archive, :unarchive, :toggle_pin, :duplicate, :merge, :export ]

      def index
        notes = current_user.accessible_notes
        notes = apply_filters(notes)
        notes = apply_sorting(notes)

        pagy, notes = pagy(notes)
        render json: { notes: notes.as_json(include_tags: true), pagination: pagy_metadata(pagy) }
      end

      def show
        render json: note_json(@note)
      end

      def create
        note = current_user.notes.build(note_params)
        if note.save
          apply_tags(note)
          render json: note_json(note), status: :created
        else
          render_validation_errors(note)
        end
      end

      def update
        unless @note.editable_by?(current_user)
          render json: { error: "Permission denied" }, status: :forbidden
          return
        end

        if @note.update(note_params)
          apply_tags(@note) if params[:tag_ids]
          render json: note_json(@note)
        else
          render_validation_errors(@note)
        end
      end

      def destroy
        unless @note.user == current_user
          render json: { error: "Only the owner can delete this note" }, status: :forbidden
          return
        end

        if @note.trashed?
          @note.destroy!
          render json: { message: "Note permanently deleted" }
        else
          @note.soft_delete!
          render json: { message: "Note moved to trash" }
        end
      end

      def restore
        @note.restore!
        render json: note_json(@note)
      end

      def archive
        @note.archive!
        render json: note_json(@note)
      end

      def unarchive
        @note.unarchive!
        render json: note_json(@note)
      end

      def toggle_pin
        @note.toggle_pin!
        render json: note_json(@note)
      end

      def duplicate
        new_note = @note.duplicate!(new_owner: current_user)
        render json: note_json(new_note), status: :created
      end

      def merge
        other_note = current_user.accessible_notes.find(params[:merge_with_id])
        @note.merge_with!(other_note)
        other_note.soft_delete!
        render json: note_json(@note)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Note to merge with not found" }, status: :not_found
      end

      def export
        render json: { filename: "#{@note.title.presence || 'untitled'}.md", content: @note.to_markdown }
      end

      def search
        if params[:q].blank?
          render json: { error: "Query parameter 'q' is required" }, status: :bad_request
          return
        end

        notes = current_user.accessible_notes.search(params[:q]).where(trashed: false)
        pagy, notes = pagy(notes)
        render json: { notes: notes.as_json(include_tags: true), pagination: pagy_metadata(pagy) }
      end

      def trash
        pagy, notes = pagy(current_user.notes.trashed.ordered)
        render json: { notes: notes.as_json(include_tags: true), pagination: pagy_metadata(pagy) }
      end

      def bulk_export
        notes = current_user.notes.where(trashed: false)
        notes = notes.where(id: params[:note_ids]) if params[:note_ids].present?

        export = notes.map do |note|
          { filename: "#{note.title.presence || "note-#{note.id}"}.md", content: note.to_markdown }
        end

        render json: { files: export }
      end

      private

      def note_params
        params.permit(:title, :body, :pinned, :max_size)
      end

      def apply_filters(notes)
        case params[:filter]
        when "pinned"
          notes.pinned.where(trashed: false)
        when "archived"
          notes.archived
        when "trash"
          notes.trashed
        else
          notes.active
        end
      end

      def apply_sorting(notes)
        case params[:sort]
        when "created_at"
          notes.order(created_at: sort_direction)
        when "title"
          notes.order(title: sort_direction)
        else
          notes.ordered
        end
      end

      def sort_direction
        params[:direction] == "asc" ? :asc : :desc
      end

      def apply_tags(note)
        if params[:tag_ids].is_a?(Array)
          note.tag_ids = params[:tag_ids].map(&:to_i) & current_user.tag_ids
        end
      end

      def note_json(note)
        note.as_json(
          include: {
            tags: { only: [ :id, :name, :color ] },
            shared_users: { only: [ :id, :name, :email ] }
          },
          methods: [ :created_at, :updated_at ]
        )
      end
    end
  end
end
