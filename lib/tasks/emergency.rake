# typed: false
# frozen_string_literal: true

namespace :app do
  namespace :emergency do
    desc "Remove api queries from before cut-over date"
    task remove_non_visible_api_queries: :environment do
      ApiQuery.where("created_at <= ?", DateTime.new(2015, 5, 7, 18, 23, 0, "+10")).delete_all
    end

    desc "Show queue / run inconsistencies - does not make any changes"
    task show_queue_run_inconsistencies: :environment do
      # TODO: Show containers that have a run label but there isn't a job on the
      # queue for that run
      # TODO: Show runs from the database that say they are running (or queued)
      # but there is no job on the queue for that run - have different handling
      # for runs that are started from a scraper and those that are started from
      # morph-cli

      puts "Getting information from sidekiq queue..."
      queue = Morph::Emergency.find_all_runs_on_the_queue

      puts "Getting information about current containers..."
      containers = Morph::Emergency.find_all_runs_associated_with_current_containers

      # Now show the differences
      puts "The following runs do not have jobs on the queue:"
      p containers - queue

      # Find runs attached to scrapers that have been queued and haven't
      # finished and don't have jobs in the queue
      unfinished = Morph::Emergency.find_all_unfinished_runs_attached_to_scrapers
      puts "Unfinished runs attached to scrapers that do not have jobs on the queue:"
      p unfinished - queue
    end

    desc "Fix queue inconsistencies - ONLY RUN THIS AFTER show_queue_run_inconsistencies"
    task fix_queue_run_inconsistencies: :environment do
      queue = Morph::Emergency.find_all_runs_on_the_queue
      unfinished = Morph::Emergency.find_all_unfinished_runs_attached_to_scrapers
      # ids of runs to delete
      runs = unfinished - queue
      puts "Putting the following runs back on the queue:"
      p runs
      runs.each { |id| RunWorker.perform_async(id) }
    end

    desc "Reset all user github access tokens (Needed after heartbleed)"
    task reset_github_access_tokens: :environment do
      User.all.each do |user|
        puts user.nickname
        user.reset_authorization!
      end
    end

    desc "Get meta info for all domains in the connection logs"
    task get_all_meta_info_for_connection_logs: :environment do
      domains = ConnectionLog.group(:host).pluck(:host)
      total = domains.count
      domains.each_with_index do |domain, index|
        if Domain.exists?(name: domain)
          puts "Skipping #{index + 1}/#{total} #{domain}"
        else
          puts "Queueing #{index + 1}/#{total} #{domain}"
          d = Domain.create!(name: domain)
          UpdateDomainWorker.perform_async(d.id)
        end
      end
    end

    desc "Delete duplicate enqueued Sidekiq scraper jobs. Sidekiq should be stopped for this to be effective"
    task delete_duplicate_scraper_jobs: :environment do
      queue = Sidekiq::Queue["scraper"].to_a
      queue.each do |x|
        if queue.count { |y| x.item["args"].first == y.item["args"].first } > 1
          puts "Deleting duplicate job for run ID: #{x.item['args'].first}..."
          x.delete
        end
      end
    end

    # See https://github.com/openaustralia/morph/issues/1038
    desc "Removed records from other tables associated with deleted scrapers"
    task fix_referential_integrity: :environment do
      def destroy_by_id(model, ids)
        progressbar = ProgressBar.create(title: model.name.pluralize, total: ids.count, format: "%t: |%B| %E")
        ids.each do |id|
          model.find(id).destroy
          progressbar.increment
        end
      end

      ids = Alert.connection.select_all("SELECT id FROM alerts WHERE watch_type = 'Scraper' AND watch_id NOT IN (SELECT id FROM scrapers)").map { |id| id["id"] }
      destroy_by_id(Alert, ids)

      ids = ApiQuery.connection.select_all("SELECT id FROM api_queries WHERE scraper_id NOT IN (SELECT id FROM scrapers)").map { |id| id["id"] }
      destroy_by_id(ApiQuery, ids)

      ids = Contribution.connection.select_all("SELECT id FROM contributions WHERE scraper_id NOT IN (SELECT id FROM scrapers)").map { |id| id["id"] }
      destroy_by_id(Contribution, ids)

      ids = Run.connection.select_all("SELECT id FROM runs WHERE scraper_id NOT IN (SELECT id FROM scrapers)").map { |id| id["id"] }
      destroy_by_id(Run, ids)

      ids = Variable.connection.select_all("SELECT id FROM variables WHERE scraper_id NOT IN (SELECT id FROM scrapers)").map { |id| id["id"] }
      destroy_by_id(Variable, ids)

      ids = Webhook.connection.select_all("SELECT id FROM webhooks WHERE scraper_id NOT IN (SELECT id FROM scrapers)").map { |id| id["id"] }
      destroy_by_id(Webhook, ids)

      ids = ConnectionLog.connection.select_all("SELECT id FROM connection_logs WHERE run_id NOT IN (SELECT id FROM runs)").map { |id| id["id"] }
      # Only try to delete 1000 at a time
      ids.each_slice(1000) do |slice|
        ConnectionLog.where(id: slice).delete_all
      end

      ids = LogLine.connection.select_all("SELECT id FROM log_lines WHERE run_id NOT IN (SELECT id FROM runs)").map { |id| id["id"] }
      ids.each_slice(1000) do |slice|
        LogLine.where(id: slice).delete_all
      end

      ids = Metric.connection.select_all("SELECT id FROM metrics WHERE run_id NOT IN (SELECT id FROM runs)").map { |id| id["id"] }
      Metric.where(id: ids).delete_all

      ids = WebhookDelivery.connection.select_all("SELECT id FROM webhook_deliveries WHERE run_id NOT IN (SELECT id FROM runs)").map { |id| id["id"] }
      WebhookDelivery.where(id: ids).delete_all

      ids = WebhookDelivery.connection.select_all("SELECT id FROM webhook_deliveries WHERE webhook_id NOT IN (SELECT id FROM webhooks)").map { |id| id["id"] }
      WebhookDelivery.where(id: ids).delete_all
    end

    desc "Clears a backlogged queue by queuing retries in a loop"
    task work_off_run_queue_retries: :environment do
      number_of_slots_to_keep_free = 4
      loop_wait_duration = 30

      while (run_retries = Sidekiq::RetrySet.new.select { |j| j.klass == "RunWorker" })
        if run_retries.count.zero?
          puts "No runs in the retry queue."
          break
        end

        puts "#{run_retries.count} in the retry queue. Checking for free slots..."
        retry_slots_available = Morph::Runner.available_slots - number_of_slots_to_keep_free

        if retry_slots_available.positive?
          puts "#{retry_slots_available} retry slots available. Queuing jobs..."
          # TODO: Should we sort this?
          run_retries.first(retry_slots_available).each(&:retry)
        else
          puts "No retry slots available. Not retrying any jobs."
        end

        puts "Waiting #{loop_wait_duration} seconds before checking again."
        sleep loop_wait_duration
      end

      puts "Retry queue cleared. Exiting."
    end
  end
end
