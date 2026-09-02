# frozen_string_literal: true

# Aggregates call activity for the reports, grouped either by agent or by inbox.
#
# The two groupings measure different things and deliberately do not reconcile.
# Per inbox, an unattended call is one nobody took. Per agent, a missed call is a
# turn the agent was given and did not answer, so one call that rang three
# agents before the fourth answered is three missed calls and zero unattended.
module Custom
  module Voice
    class CallStatsBuilder
      GROUPINGS = %i[agent inbox].freeze

      # status alone does not mean an agent spoke: a caller who joins the
      # conference and hangs up before anyone picks up still lands on
      # 'completed'. Only accepted_by_agent_id tells us a call was answered.
      ANSWERED_SQL = 'accepted_by_agent_id IS NOT NULL'

      TIME_TO_ANSWER_SQL = Arel.sql('EXTRACT(EPOCH FROM (ended_at - rang_at))')
      TIME_TO_CAPTURE_SQL = Arel.sql(
        "EXTRACT(EPOCH FROM started_at) - (calls.meta->>'initiated_at')::bigint"
      )

      pattr_initialize [:account!, :group_by!, :date_range!, { inbox_id: nil }]

      def perform
        grouping = group_by.to_sym
        raise ArgumentError, "unknown grouping: #{group_by}" unless GROUPINGS.include?(grouping)

        grouping == :agent ? rows_by_agent : rows_by_inbox
      end

      private

      # ---------- scopes ----------

      def calls
        @calls ||= begin
          scope = Custom::Call.where(account_id: account.id, created_at: date_range)
          inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope.where(inbox_id: inbox_ids)
        end
      end

      # The inboxes that do voice, taken from the calls themselves rather than
      # from channel introspection, so a chat-only inbox never shows up.
      def inbox_ids
        @inbox_ids ||= Custom::Call.where(account_id: account.id).distinct.pluck(:inbox_id)
      end

      def ring_attempts
        @ring_attempts ||= Custom::CallRingAttempt
                           .where(account_id: account.id, rang_at: date_range)
                           .where(call_id: calls.select(:id))
      end

      def call_conversation_ids
        @call_conversation_ids ||= calls.select(:conversation_id)
      end

      # Message carries a default order, which Postgres rejects once these are
      # grouped since the ordered column is not in the GROUP BY.
      def private_notes
        ::Message.reorder(nil).where(private: true, conversation_id: call_conversation_ids)
      end

      def resolved_conversations
        ::Conversation.resolved.where(id: call_conversation_ids)
      end

      # ---------- by agent ----------

      def rows_by_agent
        answered = calls.incoming.where(ANSWERED_SQL).group(:accepted_by_agent_id).count
        outbound = calls.outgoing.group(:accepted_by_agent_id).count
        minutes = calls.where(ANSWERED_SQL).group(:accepted_by_agent_id).sum(:duration_seconds)
        outbound_minutes = calls.outgoing.group(:accepted_by_agent_id).sum(:duration_seconds)
        outbound_avg = calls.outgoing.group(:accepted_by_agent_id).average(:duration_seconds)
        capture = calls.incoming.where(ANSWERED_SQL).where.not(started_at: nil)
                       .group(:accepted_by_agent_id).average(TIME_TO_CAPTURE_SQL)
        turns = ring_attempts.group(:agent_id, :outcome).count
        answer_time = ring_attempts.answered.group(:agent_id).average(TIME_TO_ANSWER_SQL)
        notes = private_notes.group(:sender_id).count
        resolved = resolved_conversations.group(:assignee_id).count

        agents.map do |agent|
          id = agent.id
          missed = Custom::CallRingAttempt::MISSED_OUTCOMES.sum { |o| turns[[id, o]].to_i }
          taken = turns[[id, Custom::CallRingAttempt::ANSWERED]].to_i

          {
            id: id,
            name: agent.available_name,
            calls_answered: answered[id].to_i,
            outbound_calls: outbound[id].to_i,
            missed_calls: missed,
            response_rate: response_rate(taken, missed),
            avg_time_to_answer: round_seconds(answer_time[id]),
            call_minutes: to_minutes(minutes[id]),
            outbound_call_minutes: to_minutes(outbound_minutes[id]),
            avg_outbound_duration: round_seconds(outbound_avg[id]),
            avg_time_to_capture: round_seconds(capture[id]),
            notes: notes[id].to_i,
            resolved_conversations: resolved[id].to_i
          }
        end
      end

      # Agents who can take calls on the inboxes in scope, so someone who
      # answered nothing in the period still shows up as a row of zeros —
      # that absence is what a supervisor is looking for.
      # Selected through a subquery rather than a join with DISTINCT: users
      # carries json columns, which Postgres cannot compare for equality.
      def agents
        @agents ||= ::User.where(
          id: ::InboxMember.where(inbox_id: inbox_id.presence || inbox_ids).select(:user_id)
        ).order(:name)
      end

      # ---------- by inbox ----------

      def rows_by_inbox
        answered = calls.incoming.where(ANSWERED_SQL).group(:inbox_id).count
        unattended = calls.incoming.where(status: 'no_answer').group(:inbox_id).count
        outbound = calls.outgoing.group(:inbox_id).count
        minutes = calls.where(ANSWERED_SQL).group(:inbox_id).sum(:duration_seconds)
        outbound_minutes = calls.outgoing.group(:inbox_id).sum(:duration_seconds)
        outbound_avg = calls.outgoing.group(:inbox_id).average(:duration_seconds)
        capture = calls.incoming.where(ANSWERED_SQL).where.not(started_at: nil)
                       .group(:inbox_id).average(TIME_TO_CAPTURE_SQL)
        answer_time = ring_attempts.answered.joins(:call).group('calls.inbox_id')
                                   .average(TIME_TO_ANSWER_SQL)
        notes = private_notes.joins(:conversation).group('conversations.inbox_id').count
        resolved = resolved_conversations.group(:inbox_id).count

        inboxes.map do |inbox|
          id = inbox.id
          {
            id: id,
            name: inbox.name,
            calls_answered: answered[id].to_i,
            unattended_calls: unattended[id].to_i,
            outbound_calls: outbound[id].to_i,
            avg_time_to_answer: round_seconds(answer_time[id]),
            call_minutes: to_minutes(minutes[id]),
            outbound_call_minutes: to_minutes(outbound_minutes[id]),
            avg_outbound_duration: round_seconds(outbound_avg[id]),
            avg_time_to_capture: round_seconds(capture[id]),
            notes: notes[id].to_i,
            resolved_conversations: resolved[id].to_i
          }
        end
      end

      def inboxes
        @inboxes ||= account.inboxes.where(id: inbox_id.presence || inbox_ids).order(:name)
      end

      # ---------- formatting ----------

      # Only turns whose outcome was the agent's to decide count here;
      # caller_hangup and superseded are excluded on both sides of the ratio.
      def response_rate(taken, missed)
        total = taken + missed
        return nil if total.zero?

        (taken.to_f / total).round(4)
      end

      def to_minutes(seconds)
        return 0.0 if seconds.blank?

        (seconds.to_f / 60).round(2)
      end

      def round_seconds(value)
        return nil if value.blank?

        value.to_f.round(1)
      end
    end
  end
end
