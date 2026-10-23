# frozen_string_literal: true

module Custom
  module Voice
    class CallRouter
      # Namespace for the reservation lock. Postgres keeps the two-argument
      # advisory lock space separate from the one-argument one, which is the
      # form DataImports::Importer uses, so these cannot collide. The value is
      # arbitrary and fixed: "VOIC" read as ASCII.
      RESERVATION_LOCK_NAMESPACE = 0x564F4943

      def initialize(inbox:, exclude_agent_ids: [], preferred_agent_id: nil)
        @inbox = inbox
        @exclude_agent_ids = Array(exclude_agent_ids).compact
        @preferred_agent_id = preferred_agent_id
      end

      # Picks an agent and writes the reservation onto the call in the same
      # breath, which next_agent on its own cannot do.
      #
      # Occupancy is read from current_ring_agent_id, and every caller used to
      # choose first and write afterwards. Two calls arriving together both read
      # before either had written, so both walked away with the same person:
      # measured over 45 days, 101 overlapping turns across 25 agents, and 82 of
      # them under one second apart — many at exactly 0,0 s, which is the
      # signature of a race and not of a rule. 48 left one of the two turns as a
      # missed call against an agent who could not have taken it, 4,67% of every
      # missed turn in the period.
      #
      # The lock is per account, not per inbox, because occupancy is: one pair
      # of ears however many inboxes somebody belongs to. It is the transaction
      # flavour, so it is released on commit and on rollback alike and cannot be
      # leaked onto a pooled connection.
      #
      # replace: an escalation is handing the turn on from the agent who let it
      # lapse, so it expects to overwrite a reservation. The first ring and the
      # waiting queue expect to find none.
      def reserve_for!(call, replace: false)
        reserved = nil

        Custom::Call.transaction do
          lock_account_reservations!
          call.reload

          if call.status == 'ringing' && (replace || call.current_ring_agent_id.nil?)
            agent = next_agent
            if agent
              call.update!(
                current_ring_agent_id: agent.id,
                meta: call.meta.merge('rang_agent_ids' => previously_rung(call) | [agent.id])
              )
              reserved = agent
            end
          end
        end

        reserved
      end

      private

      # Private since the reservation fix: picking without claiming under the
      # same lock is what the race was, so reserve_for! is the only way in.
      #
      # A preferred agent only ever jumps the queue: they still have to be
      # online, free and a member of the inbox, so a caller never waits on
      # somebody who cannot pick up. Whoever asks for one decides what earns
      # the preference; here it is only honoured when it is also eligible.
      #
      # The account-wide pause is answered here rather than in eligible_agents
      # because every reservation comes through here, so a paused account cannot
      # be reached by adding a fourth caller. See Custom::Concerns::Account.
      #
      # Returning nobody is the whole pause feature: the call is already built
      # and its conversation already exists by this point, so it stays in the
      # inbox unassigned for the team to answer by message, waits out max_wait,
      # and ends as an unattended call of the inbox with no turn opened against
      # any agent.
      def next_agent
        return nil if inbox.account.brandpatch_inbound_calls_paused?

        agents = eligible_agents
        return nil if agents.empty?

        preferred = preferred_agent_id && agents.find { |agent| agent.id == preferred_agent_id }
        preferred || round_robin_pick(agents)
      end

      def lock_account_reservations!
        Custom::Call.connection.execute(
          "SELECT pg_advisory_xact_lock(#{RESERVATION_LOCK_NAMESPACE}, #{inbox.account_id.to_i})"
        )
      end

      def previously_rung(call)
        Array(call.meta['rang_agent_ids']).map(&:to_i)
      end

      attr_reader :inbox, :exclude_agent_ids, :preferred_agent_id

      def eligible_agents
        inbox.members
             .where(id: online_agent_ids)
             .where.not(id: exclude_agent_ids + occupied_agent_ids)
      end

      # users.availability is vestigial and reads 'online' for everyone; the real
      # per-account status lives in Redis, same source core round-robin uses.
      def online_agent_ids
        statuses = ::OnlineStatusTracker.get_available_users(inbox.account_id)
        statuses.select { |_id, status| status == 'online' }.keys.map(&:to_i)
      end

      # Being on a call is a property of the agent, not of the inbox — one pair
      # of ears however many inboxes they belong to. Scoped per inbox, a call
      # arriving on inbox B rang an agent already talking on inbox A, and
      # answering it re-initialized the Twilio Device (which is per inbox and
      # destroys the previous one), dropping the first caller mid-sentence.
      #
      # `active` here is the call's own state — ringing or in_progress, the same
      # two the previous version named one by one. Reading the scope rather than
      # the statuses also covers the agent who has claimed a call that is still
      # filed as ringing: when they claimed it from the conversation the turn
      # belongs to somebody else, so current_ring_agent_id alone misses them.
      def occupied_agent_ids
        live_calls = Custom::Call.active.where(account_id: inbox.account_id)

        accepted = live_calls.where.not(accepted_by_agent_id: nil).pluck(:accepted_by_agent_id)
        being_rung = live_calls.where.not(current_ring_agent_id: nil).pluck(:current_ring_agent_id)

        (accepted + being_rung).uniq
      end

      # Fairness has to be measured over the agent's whole workload, which spans
      # every voice inbox they belong to. Scoped per inbox, an agent who had
      # just taken a call elsewhere looked like the one longest idle here and
      # was picked first, so the router preferred exactly the agent who was
      # already busy.
      def round_robin_pick(agents)
        agent_ids = agents.pluck(:id)

        last_answered_at = Custom::Call
          .where(account_id: inbox.account_id, accepted_by_agent_id: agent_ids)
          .where.not(started_at: nil)
          .group(:accepted_by_agent_id)
          .maximum(:started_at)

        sorted_id = agent_ids.min_by { |id| last_answered_at[id] || Time.at(0) }
        agents.find { |a| a.id == sorted_id }
      end
    end
  end
end
