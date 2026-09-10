# frozen_string_literal: true

module Custom
  module Voice
    class CallRouter
      def initialize(inbox:, exclude_agent_ids: [])
        @inbox = inbox
        @exclude_agent_ids = Array(exclude_agent_ids).compact
      end

      def next_agent
        agents = eligible_agents
        return nil if agents.empty?

        round_robin_pick(agents)
      end

      private

      attr_reader :inbox, :exclude_agent_ids

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
