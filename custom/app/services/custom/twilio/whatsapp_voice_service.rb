# frozen_string_literal: true

module Custom
  module Twilio
    # Connects a WhatsApp sender to the voice flow: a TwiML app that answers its
    # calls, and the sender pointed at it. Only the sender's voice configuration
    # is ever written. Its messaging webhook stays wherever it points.
    class WhatsappVoiceService
      pattr_initialize [:channel!]

      # Returns the sid of the new TwiML app.
      def connect!
        sender = find_sender
        raise 'WhatsApp sender not found in this Twilio account' unless sender

        # A sender has room for one voice app, and one Twilio account can serve
        # more than one Chatwoot (dev and production). Never take it from another.
        current = sender.configuration['voice_application_sid']
        raise "This WhatsApp sender is already connected to a voice application (#{current})" if current.present?

        app = create_twiml_app!
        point_sender_at(sender, app.sid)
        app.sid
      end

      def disconnect!
        return if channel.twiml_app_sid.blank?

        release_sender
        delete_twiml_app
        channel.update(twiml_app_sid: nil)
      rescue StandardError => e
        Rails.logger.error("TWILIO_VOICE_TEARDOWN_ERROR: #{e.class} #{e.message} phone=#{channel.phone_number} account=#{channel.account_id}")
      end

      private

      def find_sender
        channel.client.messaging.v2.channels_senders.list(channel: 'whatsapp').find { |sender| sender.sender_id == channel.phone_number }
      end

      def create_twiml_app!
        channel.client.applications.create(
          friendly_name: "Brandpatch Voice #{channel.phone_number}",
          voice_url: channel.voice_call_webhook_url, voice_method: 'POST',
          status_callback: channel.voice_status_webhook_url, status_callback_method: 'POST'
        )
      end

      def point_sender_at(sender, app_sid)
        channel.client.messaging.v2.channels_senders(sender.sid)
               .update(messaging_v2_channels_sender_requests_update: { configuration: { voice_application_sid: app_sid } })
      rescue StandardError
        channel.client.applications(app_sid).delete
        raise
      end

      # Only when the sender still points at this channel's app: if another
      # environment has taken it since, it is theirs now.
      def release_sender
        sender = find_sender
        return unless sender&.configuration&.dig('voice_application_sid') == channel.twiml_app_sid

        # An empty string clears it: Twilio reads a nil as an empty update and answers 400.
        channel.client.messaging.v2.channels_senders(sender.sid)
               .update(messaging_v2_channels_sender_requests_update: { configuration: { voice_application_sid: '' } })
      end

      def delete_twiml_app
        channel.client.applications(channel.twiml_app_sid).delete
      rescue StandardError => e
        Rails.logger.error("TWILIO_VOICE_TEARDOWN_ERROR: #{e.class} #{e.message} phone=#{channel.phone_number} account=#{channel.account_id}")
      end
    end
  end
end
