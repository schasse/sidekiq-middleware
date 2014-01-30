module Sidekiq
  module Middleware
    module Client
      class UniqueJobs
        def call(worker_class, item, queue)
          worker_class = worker_class.constantize if worker_class.is_a?(String)
          enabled = Sidekiq::Middleware::Helpers.unique_enabled?(worker_class, item)

          if enabled
            expiration = Sidekiq::Middleware::Helpers.unique_exiration(worker_class)
            job_id = item['jid']
            unique = false

            # Scheduled
            if item.has_key?('at')
              # Use expiration period as specified in configuration,
              # but relative to job schedule time
              expiration += (item['at'].to_i - Time.now.to_i)
            end

            unique_key = Sidekiq::Middleware::Helpers.unique_digest(worker_class, item)

            Sidekiq.redis do |conn|
              conn.watch(unique_key)

              locked_job_id = conn.get(unique_key)
              if locked_job_id && locked_job_id != job_id
                conn.unwatch
              else
                unique = conn.multi do
                  conn.setex(unique_key, expiration, job_id)
                end
              end
            end

            yield if unique
          else
            yield
          end
        end
      end
    end
  end
end
