# Runs every 10 minutes (config/recurring.yml). Recuts notes whose Passages were
# cut by an older version of the cutting rules, or never cut, then queues
# embedding for any Passage still missing a current embedding.
class RetrievalSweepJob < ApplicationJob
  queue_as :default

  LAST_RUN_KEY = "retrieval/last_sweep_at".freeze

  def self.last_run_at
    Rails.cache.read(LAST_RUN_KEY)
  end

  def perform
    Note.needing_passages.find_each(&:cut_passages!)
    Rails.cache.write(LAST_RUN_KEY, Time.current)
    EmbedPassagesJob.perform_later if Passage.needing_embedding.exists?
  end
end
