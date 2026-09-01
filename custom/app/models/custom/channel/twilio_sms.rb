# frozen_string_literal: true

module Custom
  module Channel
    module TwilioSms
      RING_TIMEOUT_DEFAULT = 30
      MAX_WAIT_DEFAULT = 300

      def ring_timeout_seconds
        v = provider_config['ring_timeout_seconds'].to_i
        v.positive? ? v : RING_TIMEOUT_DEFAULT
      end

      def ring_timeout_seconds=(value)
        self.provider_config = (provider_config || {}).merge('ring_timeout_seconds' => value.to_i)
      end

      def max_wait_seconds
        v = provider_config['max_wait_seconds'].to_i
        v.positive? ? v : MAX_WAIT_DEFAULT
      end

      def max_wait_seconds=(value)
        self.provider_config = (provider_config || {}).merge('max_wait_seconds' => value.to_i)
      end

      def voice_call_webhook_url
        digits = phone_number.delete_prefix('+')
        Rails.application.routes.url_helpers.custom_twilio_voice_call_url(phone: digits)
      end

      def voice_status_webhook_url
        digits = phone_number.delete_prefix('+')
        Rails.application.routes.url_helpers.custom_twilio_voice_status_url(phone: digits)
      end

      def initiate_call(to:, conference_sid: nil, agent_id: nil)
        Custom::Voice::Provider::Twilio::Adapter.new(self).initiate_call(
          to: to, conference_sid: conference_sid, agent_id: agent_id
        )
      end

      private

      def provision_twiml_app
        return if twiml_app_sid.present?
        return if phone_number.blank?

        validate_voice_capability!
        self.twiml_app_sid = Custom::Twilio::VoiceWebhookSetupService.new(channel: self).perform
      rescue StandardError => e
        Rails.logger.error("TWILIO_VOICE_SETUP_ERROR: #{e.class} #{e.message} phone=#{phone_number} account=#{account_id}")
        errors.add(:base, "Twilio voice setup failed: #{e.message}")
      end

      # Overrides the alias Enterprise sets so our provision_twiml_app is used on update too.
      def provision_twiml_app_on_update
        provision_twiml_app
      end

      def teardown_voice
        Custom::Twilio::VoiceTeardownService.new(channel: self).perform
      end
    end
  end
end
