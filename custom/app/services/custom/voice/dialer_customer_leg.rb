# frozen_string_literal: true

# The customer's side of an auto-dialer call: dialling them once their agent is
# in the conference, and hanging up on an answering machine.
#
# meta['dialer']['phase'] walks awaiting_agent -> dialing, and nothing else
# moves it: a call that ends before its agent joins keeps awaiting_agent, which
# is how a reader tells a customer who was never dialled from one who did not
# pick up.
module Custom
  module Voice
    class DialerCustomerLeg
      MACHINE_ENDING = 'machine'

      pattr_initialize [:call!]

      # Called from the agent's participant-join. The phase flips under the row
      # lock before Twilio is asked, so a second join — a reconnect, a second
      # tab, Twilio repeating the callback — finds 'dialing' and dials nobody.
      # The Twilio request itself stays outside the lock.
      #
      # A number Twilio refuses outright (malformed, not dialable from this
      # account) is refused here, synchronously, before any status callback
      # exists to report it. The call then fails through the single entry point
      # with the reason the status webhook would have recorded, and the
      # conference is closed so the agent is not left on hold music.
      def dial!
        return unless claim_dial!

        adapter = Custom::Voice::Provider::Twilio::Adapter.new(call.inbox.channel)
        sid = adapter.initiate_dialer_call(to: call.contact.phone_number, dialer_sid: call.provider_call_id)
        call.merge_dialer!('customer_call_sid' => sid, 'dialed_at' => Time.zone.now.to_i)
      rescue ::Twilio::REST::RestError => e
        fail_dial!(e)
      end

      # Async AMD reports after the customer is already in the conference, so a
      # human needs nothing: they are talking to the agent. A machine — or a
      # fax — is hung up on, which also drops the agent out of the conference;
      # the call then ends through the ordinary status flow, and end_reason is
      # stamped first so it survives whichever writer gets there.
      def record_answered_by!(answered_by)
        machine = answered_by.to_s.start_with?('machine') || answered_by == 'fax'
        call.merge_dialer!({ 'answered_by' => answered_by }.merge(machine ? { 'end_reason' => MACHINE_ENDING } : {}))
        return unless machine

        Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
      end

      private

      def fail_dial!(error)
        Rails.logger.info("VOICE_DIALER_DIAL_FAILED: call=#{call.id} code=#{error.code} #{error.message}")
        Custom::Voice::CallStatus::Manager.new(call: call).process_status_update(
          'failed', failure: { reason: Custom::Call.failure_reason_for(error.code), error_code: error.code.to_s }
        )
        Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
        call.broadcast_voice_call_event(:ended, status: call.display_status)
      end

      def claim_dial!
        call.with_lock do
          next false if call.terminal? || call.dialer['phase'] != 'awaiting_agent'

          call.update!(dialer: call.dialer.merge('phase' => 'dialing'))
          true
        end
      end
    end
  end
end
