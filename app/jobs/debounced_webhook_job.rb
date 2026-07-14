class DebouncedWebhookJob < ApplicationJob
  queue_as :medium

  def perform(webhook_id, contact_id, expected_version)
    version_key = format(Redis::RedisKeys::WEBHOOK_DEBOUNCE_VERSION, webhook_id: webhook_id, contact_id: contact_id)
    current_version = Redis::Alfred.get(version_key).to_i

    return if current_version != expected_version

    batch_key = format(Redis::RedisKeys::WEBHOOK_DEBOUNCE_BATCH, webhook_id: webhook_id, contact_id: contact_id)
    raw_payloads = Redis::Alfred.lrange(batch_key)

    return if raw_payloads.blank?

    webhook = Webhook.find_by(id: webhook_id)
    return if webhook.nil?

    messages = raw_payloads.map { |raw| JSON.parse(raw, symbolize_names: true) }
    batch_payload = { event: 'message_created', messages: messages }

    Redis::Alfred.delete(batch_key)
    Redis::Alfred.delete(version_key)

    Webhooks::Trigger.execute(webhook.url, batch_payload, :account_webhook,
                              secret: webhook.secret, delivery_id: SecureRandom.uuid)
  end
end
