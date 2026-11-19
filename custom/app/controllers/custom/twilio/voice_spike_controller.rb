# frozen_string_literal: true

# COM-1607 spike, throwaway: never merged to develop. It answers the calls that
# Twilio forwards from a WhatsApp sender with the same flow a phone call gets,
# on a fixed voice inbox, and writes down everything Twilio sends so what the
# docs leave out (the webhook params, the From format, the callbacks) is known.
module Custom
  module Twilio
    class VoiceSpikeController < VoiceController
      SPIKE_INBOX_ID = 11

      prepend_before_action :capture_request

      def capture_only
        head :no_content
      end

      private

      def capture_request
        set_inbox!
        validator = ::Twilio::Security::RequestValidator.new(inbox_channel.auth_token)
        entry = { at: Time.current.iso8601(3), action: action_name, url: request.original_url, user_agent: request.user_agent,
                  signature_valid: validator.validate(request.original_url, request.POST, request.headers['X-Twilio-Signature'].to_s),
                  params: params.to_unsafe_h.except(:controller, :action) }
        Rails.logger.info("SPIKE_WA #{entry.to_json}")
      end

      def set_inbox!
        @inbox = ::Inbox.find(SPIKE_INBOX_ID)
      end

      def twilio_from
        super.delete_prefix('whatsapp:')
      end

      # Whatever Direction a WhatsApp call arrives with, it is handled as inbound:
      # the capture above has already written down the real value.
      def twilio_direction
        super.presence_in(%w[inbound outbound-api outbound-dial]) || 'inbound'
      end
    end
  end
end
