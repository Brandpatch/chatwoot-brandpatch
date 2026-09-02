# frozen_string_literal: true

# Records each ring turn so the reports can measure per-agent response rate.
# A call has at most one open turn at a time, mirroring current_ring_agent_id.
module Custom
  module Voice
    class RingAttemptTracker
      class << self
        def open!(call, agent_id)
          Custom::CallRingAttempt.create!(
            account_id: call.account_id,
            call_id: call.id,
            agent_id: agent_id,
            rang_at: Time.zone.now
          )
        end

        # An agent who connected and served the call answered it, even when the
        # escalation clock closed their turn a moment before their click landed.
        # Their turn is resolved as the answer regardless of how it was already
        # closed, and any turn left open belongs to an agent the call moved past.
        # Outbound calls have no turn to resolve, so nothing is created here.
        def record_answer!(call, agent_id)
          Custom::CallRingAttempt
            .where(call_id: call.id, agent_id: agent_id)
            .order(:id)
            .last
            &.update!(outcome: Custom::CallRingAttempt::ANSWERED, ended_at: Time.zone.now)

          close!(call, Custom::CallRingAttempt::SUPERSEDED, except_agent_id: agent_id)
        end

        # Filters on ended_at being nil, so the first close for a turn wins and
        # overlapping paths (an escalation racing the caller hanging up) can't
        # relabel a turn that already resolved. Pass agent_id where the outcome
        # belongs to a specific agent, so a late join by a previous agent doesn't
        # get credited with someone else's answer.
        def close!(call, outcome, agent_id: nil, except_agent_id: nil)
          scope = Custom::CallRingAttempt.unfinished.where(call_id: call.id)
          scope = scope.where(agent_id: agent_id) if agent_id
          scope = scope.where.not(agent_id: except_agent_id) if except_agent_id

          scope.update_all(outcome: outcome, ended_at: Time.zone.now, updated_at: Time.zone.now) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
  end
end
