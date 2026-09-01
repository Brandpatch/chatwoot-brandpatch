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

      def occupied_agent_ids
        on_call = Custom::Call.where(inbox_id: inbox.id, status: 'in_progress')
                              .where.not(accepted_by_agent_id: nil)
                              .pluck(:accepted_by_agent_id)

        ringing = Custom::Call.where(inbox_id: inbox.id, status: 'ringing')
                              .where.not(current_ring_agent_id: nil)
                              .pluck(:current_ring_agent_id)

        (on_call + ringing).uniq
      end

      def round_robin_pick(agents)
        agent_ids = agents.pluck(:id)

        last_answered_at = Custom::Call
          .where(inbox_id: inbox.id, accepted_by_agent_id: agent_ids)
          .where.not(started_at: nil)
          .group(:accepted_by_agent_id)
          .maximum(:started_at)

        sorted_id = agent_ids.min_by { |id| last_answered_at[id] || Time.at(0) }
        agents.find { |a| a.id == sorted_id }
      end
    end
  end
end
