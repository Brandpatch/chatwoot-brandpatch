# frozen_string_literal: true

# Moves a ringing call past the agent it is currently offered to: on to the next
# eligible agent, or to nobody, in which case the caller keeps waiting in the
# conference until max_wait expires. The ring timeout and an agent declining
# from the widget differ only in why the departing turn closed, which is what
# `outcome` carries.
module Custom
  module Voice
    class CallEscalationService
      pattr_initialize [:call!, :outcome!]

      def perform
        rang_ids = Array(call.meta['rang_agent_ids']).map(&:to_i)
        next_agent = Custom::Voice::CallRouter.new(inbox: call.inbox, exclude_agent_ids: rang_ids).next_agent

        next_agent ? assign_to_agent!(next_agent, rang_ids) : unassign!
      end

      private

      def assign_to_agent!(agent, rang_ids)
        previous_agent_id = call.current_ring_agent_id

        call.with_lock do
          return unless call.status == 'ringing'

          call.update!(
            current_ring_agent_id: agent.id,
            meta: call.meta.merge('rang_agent_ids' => rang_ids | [agent.id])
          )
        end

        Custom::Voice::RingAttemptTracker.close!(call, outcome, agent_id: previous_agent_id)
        Custom::Voice::RingAttemptTracker.open!(call, agent.id)

        call.broadcast_voice_call_event(:ring_reassigned,
                                        previous_agent_id: previous_agent_id,
                                        current_ring_agent_id: agent.id)

        arm_timeout!(agent.id)
      end

      def unassign!
        call.with_lock do
          return unless call.status == 'ringing'

          call.update!(current_ring_agent_id: nil)
        end

        Custom::Voice::RingAttemptTracker.close!(call, outcome)
        call.broadcast_voice_call_event(:unassigned)

        # No agent left to ring, but the caller keeps waiting until max_wait.
        # Re-arm the job so the max_wait expiry still fires.
        arm_timeout!(nil)
      end

      def arm_timeout!(agent_id)
        Custom::Voice::CallRingTimeoutJob
          .set(wait: call.inbox.channel.ring_timeout_seconds.seconds)
          .perform_later(call.id, agent_id)
      end
    end
  end
end
