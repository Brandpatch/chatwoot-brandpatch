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
          escalate!(call)
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

      def escalate!(call)
        rang_ids = Array(call.meta['rang_agent_ids']).map(&:to_i)
        next_agent = Custom::Voice::CallRouter.new(inbox: call.inbox, exclude_agent_ids: rang_ids).next_agent

        if next_agent
          assign_to_agent!(call, next_agent, rang_ids)
        else
          unassign!(call)
        end
      end

      def assign_to_agent!(call, agent, rang_ids)
        previous_agent_id = call.current_ring_agent_id

        call.with_lock do
          return unless call.status == 'ringing'

          call.update!(
            current_ring_agent_id: agent.id,
            meta: call.meta.merge('rang_agent_ids' => rang_ids | [agent.id])
          )
        end

        Custom::Voice::RingAttemptTracker.close!(call, Custom::CallRingAttempt::TIMEOUT,
                                                 agent_id: previous_agent_id)
        Custom::Voice::RingAttemptTracker.open!(call, agent.id)

        call.broadcast_voice_call_event(:ring_reassigned,
                                        previous_agent_id: previous_agent_id,
                                        current_ring_agent_id: agent.id)

        CallRingTimeoutJob.set(wait: call.inbox.channel.ring_timeout_seconds.seconds)
                          .perform_later(call.id, agent.id)
      end

      def unassign!(call)
        call.with_lock do
          return unless call.status == 'ringing'

          call.update!(current_ring_agent_id: nil)
        end

        Custom::Voice::RingAttemptTracker.close!(call, Custom::CallRingAttempt::TIMEOUT)
        call.broadcast_voice_call_event(:unassigned)

        # No agent left to ring, but the caller keeps waiting until max_wait.
        # Re-arm the job so the max_wait expiry still fires.
        CallRingTimeoutJob.set(wait: call.inbox.channel.ring_timeout_seconds.seconds)
                          .perform_later(call.id, nil)
      end
    end
  end
end
