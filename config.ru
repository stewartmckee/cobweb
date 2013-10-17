
if Gem::Specification.find_all_by_name("sidekiq", ">=1.0.0").count > 1

  require 'sidekiq'

  Sidekiq.configure_client do |config|
    config.redis = { :size => 1 }
  end

  require 'sidekiq/web'
  run Sidekiq::Web
end