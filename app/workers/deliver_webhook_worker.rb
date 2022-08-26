# typed: strict
# frozen_string_literal: true

class DeliverWebhookWorker
  extend T::Sig

  include Sidekiq::Worker
  sidekiq_options backtrace: true

  sig { params(webhook_delivery_id: Integer).void }
  def perform(webhook_delivery_id)
    webhook_delivery = WebhookDelivery.find(webhook_delivery_id)
    # TODO: As soon as we've upgraded to a recent version of Ubuntu switch the SSL
    # verification back on. It's not crazy-super important that we verify SSL with
    # webhooks but it's sure a good idea.
    connection = Faraday.new(webhook_delivery.webhook.url, ssl: { verify: false })
    begin
      response = connection.post
      webhook_delivery.update(
        response_code: response.status,
        sent_at: DateTime.now
      )
    rescue Faraday::ConnectionFailed => e
      # Swallow connection failures to a webhook so that they don't show up alongside other much
      # more important errors. Also, we don't want these just constantly retrying after failures
      Rails.logger.error("Webhook delivery failure on scraper #{webhook_delivery.run.scraper.full_name}: #{e}")
    end
  end
end
