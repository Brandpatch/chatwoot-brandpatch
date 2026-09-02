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

        # Closing filters on ended_at being nil, so the first close for a turn wins
        # and overlapping paths (an escalation racing the caller hanging up) can't
        # relabel a turn that already resolved. Pass agent_id where the outcome
        # belongs to a specific agent, so a late join by a previous agent doesn't
        # get credited with someone else's answer.
        def close!(call, outcome, agent_id: nil)
          scope = Custom::CallRingAttempt.unfinished.where(call_id: call.id)
          scope = scope.where(agent_id: agent_id) if agent_id

          scope.update_all(outcome: outcome, ended_at: Time.zone.now, updated_at: Time.zone.now) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
  end
end
