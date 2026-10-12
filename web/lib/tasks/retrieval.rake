namespace :retrieval do
  desc "Download the pinned embedding model for Retrieval into vendor/models, unless already installed"
  task install_model: :environment do
    if Retrieval::Embedder.install!
      puts "Installed #{Retrieval::Embedder::MODEL} (#{Retrieval::Embedder::REVISION}) in #{Retrieval::Embedder::DIR}"
    else
      puts "#{Retrieval::Embedder::MODEL} already installed"
    end
  end
end
