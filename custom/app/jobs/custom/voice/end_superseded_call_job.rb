# frozen_string_literal: true

module Custom
  module Voice
    # A customer who gets tired of the ring hangs up and dials again, and the
    # call they walked away from stays offerable. It keeps its own conference,
    # so an agent who takes it lands alone in a room with hold music while the
    # customer waits on the new line: two agents busy, nobody talking to
    # anybody. That is what customer service reported as a call falling on two
    # agents at once. Measured over 21 days: 9 overlapping pairs, 5 of them with
    # two different agents, and the old call stays live for up to 235 seconds.
    #
    # Out of band rather than inside InboundCallBuilder for two reasons: it
    # keeps a pair of Twilio round trips off the webhook that is answering the
    # new call, and it keeps a failure here from becoming a 500 that hangs up on
    # a customer who did nothing wrong.
    class EndSupersededCallJob < ApplicationJob
      queue_as :default

      def perform(call_id)
        call = Custom::Call.find_by(id: call_id)
        return unless call
        return if call.terminal?

        # Take the turn away first, so the call stops being offered before the
        # provider teardown, which is the slow part.
        call.update!(current_ring_agent_id: nil)
        call.broadcast_voice_call_event(:unassigned)
        Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
        # The single entry point takes it terminal and closes the turn still
        # open as caller_hangup — which is what happened, and is not held
        # against the agent it was ringing.
        Custom::Voice::CallStatus::Manager.new(call: call).process_status_update('no_answer')
      end
    end
  end
end
