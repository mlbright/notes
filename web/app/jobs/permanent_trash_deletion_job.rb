class PermanentTrashDeletionJob < ApplicationJob
  queue_as :default

  def perform
    deleted_count = Note.stale_trash.destroy_all.size
    Rails.logger.info "PermanentTrashDeletionJob: Deleted #{deleted_count} trashed notes older than 30 days"
  end
end
