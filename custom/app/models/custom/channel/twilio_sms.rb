# frozen_string_literal: true

module Custom
  module Channel
    module TwilioSms
      RING_TIMEOUT_DEFAULT = 30
      MAX_WAIT_DEFAULT = 300

      def self.prepended(base)
        base.validate :voice_caller_id_must_be_available, if: :will_save_change_to_provider_config?
      end

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

      # [brandpatch] Per-inbox switch for the voice IVR's language menu
      # (T4, not yet built), so the feature can be turned on inbox by inbox
      # instead of for all voice inboxes at once. Off by default.
      def voice_language_menu_enabled?
        provider_config['voice_language_menu_enabled'] == true
      end

      def voice_language_menu_enabled=(value)
        self.provider_config = (provider_config || {}).merge(
          'voice_language_menu_enabled' => ActiveModel::Type::Boolean.new.cast(value)
        )
      end

      # [brandpatch] The number the customer sees when an agent calls out from
      # this inbox. Blank means the inbox's own number, which is what every
      # inbox did before this existed. It only changes what is sent as the
      # call's from: the webhooks stay keyed by the inbox's own number, so
      # nothing about routing moves with it.
      def voice_caller_id
        provider_config['voice_caller_id'].presence
      end

      def voice_caller_id=(value)
        self.provider_config = (provider_config || {}).except('voice_caller_id').merge(
          value.present? ? { 'voice_caller_id' => value.strip } : {}
        )
      end

      # What Twilio accepts as a from on this account: the inbox's own number and
      # the numbers verified as caller IDs. Anything else is refused by Twilio
      # with a 21210 at the moment of dialling, which is the worst place to find
      # out, so a value is checked against this when it is saved.
      def available_voice_caller_ids
        verified = client.outgoing_caller_ids.list.map do |caller_id|
          { phone_number: caller_id.phone_number, friendly_name: caller_id.friendly_name }
        end
        [{ phone_number: phone_number, friendly_name: phone_number }] + verified.reject { |number| number[:phone_number] == phone_number }
      end

      # What identifies this inbox in the voice webhook URLs. A WhatsApp sender
      # can share its number with an SMS inbox, so those two get different keys.
      def voice_webhook_key
        whatsapp? ? "whatsapp-#{phone_number.delete_prefix('whatsapp:+')}" : phone_number.delete_prefix('+')
      end

      def voice_call_webhook_url
        Rails.application.routes.url_helpers.custom_twilio_voice_call_url(phone: voice_webhook_key)
      end

      def voice_status_webhook_url
        Rails.application.routes.url_helpers.custom_twilio_voice_status_url(phone: voice_webhook_key)
      end

      def initiate_call(to:, conference_sid: nil, agent_id: nil)
        Custom::Voice::Provider::Twilio::Adapter.new(self).initiate_call(
          to: to, conference_sid: conference_sid, agent_id: agent_id
        )
      end

      private

      # Only a value that is being set now is checked: one saved earlier that
      # Twilio has since dropped must not stop the inbox's other settings from
      # being saved, and it shows up on the next call instead.
      def voice_caller_id_must_be_available
        return if voice_caller_id.blank? || voice_caller_id == provider_config_was&.dig('voice_caller_id')
        return if available_voice_caller_ids.any? { |number| number[:phone_number] == voice_caller_id }

        errors.add(:base, 'The outgoing number is not this inbox number or a caller ID verified in its Twilio account')
      rescue ::Twilio::REST::TwilioError
        errors.add(:base, 'The outgoing number could not be checked against Twilio. Please try again.')
      end

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
