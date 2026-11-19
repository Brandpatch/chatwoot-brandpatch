# frozen_string_literal: true

module Custom
  module Voice
    # The auto-dialer reserves an agent and waits for their browser to join
    # before dialling the customer. A browser that never joins — tab closed,
    # microphone blocked, the socket down when the assignment was sent — would
    # otherwise keep that agent busy for good, since nothing else ends a call
    # whose customer was never dialled.
    #
    # Ends as 'failed' because no call was ever placed: 'no_answer' would read
    # as a customer who did not pick up. The customer was never dialled, so
    # there is nobody to hang up on; the conference is closed anyway in case the
    # agent got in just as this ran and their join is still on its way.
    class DialerAgentJoinTimeoutJob < ApplicationJob
      queue_as :default

      AGENT_DID_NOT_JOIN = 'agent_did_not_join'

      def perform(call_id)
        call = Custom::Call.find_by(id: call_id)
        return unless call

        expired = call.with_lock do
          next false if call.terminal? || call.dialer['phase'] != 'awaiting_agent'

          # Terminal before the lock is released, so a join landing right now
          # finds the call over and DialerCustomerLeg#dial! dials nobody.
          call.update!(dialer: call.dialer.merge('end_reason' => AGENT_DID_NOT_JOIN))
          Custom::Voice::CallStatus::Manager.new(call: call).process_status_update('failed')
          true
        end
        return unless expired

        Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
        call.broadcast_voice_call_event(:ended, status: call.display_status)
      end
    end
  end
end
