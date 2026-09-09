# frozen_string_literal: true

module Custom
  module Voice
    class CallRingTimeoutJob < ApplicationJob
      queue_as :default

      def perform(call_id, expected_agent_id)
        call = Custom::Call.find_by(id: call_id)
        return unless call
        return unless call.status == 'ringing'
        return unless call.current_ring_agent_id == expected_agent_id

        if max_wait_exceeded?(call)
          expire_call!(call)
        else
          Custom::Voice::CallEscalationService.new(call: call, outcome: Custom::CallRingAttempt::TIMEOUT).perform
        end
      end

      private

      def max_wait_exceeded?(call)
        initiated_at = call.meta['initiated_at'].to_i
        return false if initiated_at.zero?

        Time.zone.now.to_i - initiated_at >= call.inbox.channel.max_wait_seconds
      end

      def expire_call!(call)
        # Close before the status update: an agent may still be mid-turn when
        # max_wait lands, and that turn lapsed on them rather than on the caller.
        Custom::Voice::RingAttemptTracker.close!(call, Custom::CallRingAttempt::TIMEOUT)
        call.update!(current_ring_agent_id: nil)
        call.broadcast_voice_call_event(:unassigned)
        Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
        Custom::Voice::CallStatus::Manager.new(call: call).process_status_update('no_answer')
      end
    end
  end
end
