class NotesController < ApplicationController
  before_action :require_login
  before_action :set_note, only: [ :show, :edit, :update, :destroy, :restore, :archive, :unarchive, :toggle_pin, :toggle_checklist, :toggle_checklist_item, :duplicate, :merge, :export ]
  before_action :require_edit_permission, only: [ :edit, :update, :archive, :unarchive, :toggle_pin, :toggle_checklist, :toggle_checklist_item ]

  def index
    notes = current_user.accessible_notes

    notes = apply_filters(notes)
    notes = notes.ordered

    @pagy, @notes = pagy(notes)
  end

  def show
  end

  def new
    @note = current_user.notes.build
  end

  def create
    @note = current_user.notes.build(note_params)

    if @note.save
      apply_tags(@note)
      redirect_to @note, notice: "Note created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @note.update(note_params)
      apply_tags(@note)
      redirect_to @note, notice: "Note updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @note.user == current_user
      if @note.trashed?
        @note.destroy!
        redirect_to notes_path(filter: "trash"), notice: "Note permanently deleted."
      else
        @note.soft_delete!
        redirect_to notes_path, notice: "Note moved to trash."
      end
    else
      redirect_to notes_path, alert: "Only the owner can delete this note."
    end
  end

  def restore
    @note.restore!
    redirect_to notes_path, notice: "Note restored."
  end

  def archive
    @note.archive!
    redirect_to notes_path, notice: "Note archived."
  end

  def unarchive
    @note.unarchive!
    redirect_to notes_path, notice: "Note unarchived."
  end

  def toggle_pin
    @note.toggle_pin!
    redirect_back fallback_location: notes_path
  end

  def toggle_checklist
    @note.toggle_checklist!
    redirect_back fallback_location: @note
  end

  def toggle_checklist_item
    line_index = params[:line_index].to_i
    @note.toggle_checklist_item!(line_index)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("checklist_body", partial: "notes/checklist_body", locals: { note: @note }) }
      format.html { redirect_back fallback_location: @note }
    end
  end

  def duplicate
    new_note = @note.duplicate!(new_owner: current_user)
    redirect_to new_note, notice: "Note duplicated."
  end

  def merge
    other_note = current_user.accessible_notes.find(params[:merge_with_id])
    @note.merge_with!(other_note)
    other_note.soft_delete!
    redirect_to @note, notice: "Notes merged."
  rescue ActiveRecord::RecordNotFound
    redirect_to @note, alert: "Could not find the note to merge with."
  end

  def export
    send_data @note.to_markdown,
      filename: "#{@note.title.presence || 'untitled'}.md",
      type: "text/markdown"
  end

  def bulk_export
    notes = current_user.notes.where(trashed: false)
    notes = notes.where(id: params[:note_ids]) if params[:note_ids].present?

    export_data = notes.map do |note|
      { filename: "#{note.title.presence || "note-#{note.id}"}.md", content: note.to_markdown }
    end

    zip_data = generate_zip(export_data)
    send_data zip_data, filename: "notes-export-#{Date.current}.zip", type: "application/zip"
  end

  def search
    if params[:q].present?
      notes = current_user.accessible_notes.search(params[:q]).where(trashed: false)
      @pagy, @notes = pagy(notes)
    else
      @notes = []
    end
  end

  def trash
    @pagy, @notes = pagy(current_user.notes.trashed.ordered)
  end

  private

  def note_params
    params.require(:note).permit(:title, :body, :pinned, :checklist, :max_size, attachments: [], tag_ids: [])
  end

  def apply_tags(note)
    if params[:note]&.key?(:tag_ids)
      tag_ids = Array(params[:note][:tag_ids]).reject(&:blank?).map(&:to_i)
      note.tag_ids = tag_ids & current_user.tag_ids
    end
  end

  def require_edit_permission
    unless @note.editable_by?(current_user)
      redirect_to @note, alert: "You don't have permission to edit this note."
    end
  end

  def apply_filters(notes)
    notes = case params[:filter]
    when "pinned"
      notes.pinned.where(trashed: false)
    when "archived"
      notes.archived
    when "trash"
      notes.trashed
    else
      notes.active
    end

    if params[:tag].present?
      tag = current_user.tags.find_by(name: params[:tag])
      notes = notes.joins(:note_tags).where(note_tags: { tag_id: tag.id }) if tag
    end

    notes
  end

  def generate_zip(files)
    require "zip"
    buffer = StringIO.new
    Zip::OutputStream.write_buffer(buffer) do |zip|
      files.each do |file|
        zip.put_next_entry(file[:filename])
        zip.write(file[:content])
      end
    end
    buffer.string
  rescue LoadError
    # Fallback: just concatenate files if rubyzip not available
    files.map { |f| "--- #{f[:filename]} ---\n\n#{f[:content]}\n\n" }.join
  end
end
