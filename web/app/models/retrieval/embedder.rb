# Turns text into embeddings with a small local model, run in-process by ONNX
# Runtime (see docs/adr/0003). The model is installed into vendor/models by
# `bin/rails retrieval:install_model` (run by `make update`) and is never
# downloaded at runtime.
#
# ONNX Runtime holds Ruby's GVL for the whole of each call, so documents are
# only embedded in Solid Queue jobs, which run in their own process; queries are
# short enough to embed inside a request. Each kind loads its own copy of the
# model on first use, so a Puma process only ever holds the query copy and the
# job worker only the document copy. Loading lazily also keeps the model out of
# the Puma process that Solid Queue forks from.
class Retrieval::Embedder
  class Unavailable < StandardError; end

  MODEL = "Xenova/bge-small-en-v1.5"
  REVISION = "ea104dacec62c0de699686887e3f920caeb4f3e3"
  DTYPE = "q8"
  DIR = Rails.root.join("vendor/models")
  FILES = %w[config.json tokenizer.json tokenizer_config.json onnx/model_quantized.onnx].freeze

  # bge models embed queries with an instruction prefix and documents without.
  QUERY_PREFIX = "Represent this sentence for searching relevant passages: ".freeze

  # Documents get 2 threads, leaving the other cores to web requests while the
  # sweep catches up.
  SESSION_OPTIONS = {
    query: { enable_cpu_mem_arena: false },
    document: { intra_op_num_threads: 2, enable_cpu_mem_arena: false }
  }.freeze

  def self.installed?
    FILES.all? { |file| DIR.join(MODEL, REVISION, file).file? }
  end

  # Downloads the pinned model revision unless it is already installed.
  def self.install!
    return false if installed?

    require "informers"
    Informers.allow_remote_models = true
    Informers.pipeline("embedding", MODEL, revision: REVISION, dtype: DTYPE, cache_dir: DIR.to_s)
    true
  ensure
    Informers.allow_remote_models = false if defined?(Informers)
  end

  def initialize
    @pipelines = {}
    @lock = Mutex.new
  end

  # Identifies the model that produced an embedding. Embeddings from any other
  # model are ignored by Retrieval and recomputed by the sweep.
  def model_key
    "#{MODEL}@#{REVISION.first(7)}/#{DTYPE}"
  end

  def embed_query(text)
    pipeline(:query).(QUERY_PREFIX + text, pooling: "cls")
  end

  def embed_document(text)
    pipeline(:document).(text, pooling: "cls")
  end

  private

  def pipeline(kind)
    @pipelines[kind] || @lock.synchronize { @pipelines[kind] ||= load_pipeline(kind) }
  end

  def load_pipeline(kind)
    raise Unavailable, "embedding model not installed in #{DIR}; run bin/rails retrieval:install_model" unless self.class.installed?

    require "informers"
    Informers.allow_remote_models = false
    Informers.pipeline(
      "embedding", MODEL,
      revision: REVISION, dtype: DTYPE, cache_dir: DIR.to_s, local_files_only: true,
      progress_callback: nil, session_options: SESSION_OPTIONS.fetch(kind)
    )
  rescue Unavailable
    raise
  rescue StandardError => e
    raise Unavailable, "could not load embedding model: #{e.message}"
  end
end
