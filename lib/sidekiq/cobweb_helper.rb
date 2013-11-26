
if Gem::Specification.find_all_by_name("sidekiq", ">=1.0.0").count >= 1
  SIDEKIQ_INSTALLED = true
  require 'sidekiq'
else
  SIDEKIQ_INSTALLED = false
  puts "sidekiq gem not installed, skipping crawl_worker specs"
end

module Sidekiq
  module Worker
    module ClassMethods
      def queue_size
        Sidekiq.redis do |conn|
          conn.llen("queue:#{get_sidekiq_options["queue"]}")
        end
      end
      def queue_items(start=0, finish=-1)
        Sidekiq.redis do |conn|
          conn.lrange("queue:#{get_sidekiq_options["queue"]}", start, finish)
        end
      end
    end
  end
end