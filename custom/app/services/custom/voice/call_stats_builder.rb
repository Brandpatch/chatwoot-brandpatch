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

      # How long an agent took on a turn that was offered to them, measured over
      # call_ring_attempts. Only meaningful per agent: an inbox has no turns.
      TIME_TO_ANSWER_SQL = Arel.sql('EXTRACT(EPOCH FROM (ended_at - rang_at))')

      # How long the customer waited in total, from the call reaching us to an
      # agent picking up. This is the inbox's answer: averaging the agents' own
      # reaction times hides every turn that lapsed before somebody answered,
      # so a call that rang three agents looks as quick as one answered at once.
      CUSTOMER_WAIT_SQL = Arel.sql(
        "EXTRACT(EPOCH FROM started_at) - (calls.meta->>'initiated_at')::bigint"
      )

      pattr_initialize [:account!, :group_by!, :date_range!, { inbox_id: nil }]

      def perform
        grouping = group_by.to_sym
        raise ArgumentError, "unknown grouping: #{group_by}" unless GROUPINGS.include?(grouping)

        {
          totals: totals,
          rows: grouping == :agent ? rows_by_agent : rows_by_inbox
        }
      end

      # Period figures for the whole scope, so the summary answers "how did we
      # do" without the reader adding up a column. They are inbox-level on
      # purpose: received and unattended have no per-agent meaning, and the
      # response rate across everyone is not the average of the per-agent ones.
      def totals
        turns = ring_attempts.group(:outcome).count
        taken = turns[Custom::CallRingAttempt::ANSWERED].to_i
        missed = Custom::CallRingAttempt::MISSED_OUTCOMES.sum { |o| turns[o].to_i }

        {
          received_calls: calls.incoming.where(status: Custom::Call::TERMINAL_STATUSES).count,
          calls_answered: calls.incoming.answered.count,
          unattended_calls: unattended_calls.count,
          response_rate: response_rate(taken, missed),
          avg_time_to_answer: round_seconds(answered_incoming_calls.average(CUSTOMER_WAIT_SQL)),
          call_minutes: to_minutes(calls.answered.sum(:duration_seconds)),
          outbound_calls: calls.outgoing.count,
          outbound_call_minutes: to_minutes(calls.outgoing.sum(:duration_seconds))
        }
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

      # Every inbound call that ended with no agent on it: the ones that timed
      # out, the ones an agent declined, and the ones where the caller gave up
      # after entering the conference. Taken as the complement of answered so
      # the two columns always account for every call the inbox received,
      # including whatever status the provider invents next.
      def unattended_calls
        calls.incoming
             .where(status: Custom::Call::TERMINAL_STATUSES)
             .unanswered
      end

      # Answered inbound calls that can say how long the customer waited. A call
      # with no started_at never reached an agent, so it has no wait to average.
      def answered_incoming_calls
        @answered_incoming_calls ||= calls.incoming.answered.where.not(started_at: nil)
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
        answered = calls.incoming.answered.group(:accepted_by_agent_id).count
        outbound = calls.outgoing.group(:accepted_by_agent_id).count
        minutes = calls.answered.group(:accepted_by_agent_id).sum(:duration_seconds)
        outbound_minutes = calls.outgoing.group(:accepted_by_agent_id).sum(:duration_seconds)
        outbound_avg = calls.outgoing.group(:accepted_by_agent_id).average(:duration_seconds)
        turns = ring_attempts.group(:agent_id, :outcome).count
        answer_time = ring_attempts.answered.group(:agent_id).average(TIME_TO_ANSWER_SQL)
        notes = private_notes.group(:sender_id).count
        resolved = resolved_conversations.group(:assignee_id).count

        rows = agents.map do |agent|
          id = agent.id
          missed = Custom::CallRingAttempt::MISSED_OUTCOMES.sum { |o| turns[[id, o]].to_i }
          taken = turns[[id, Custom::CallRingAttempt::ANSWERED]].to_i

          {
            id: id,
            name: agent.available_name,
            email: agent.email,
            # Availability is deliberately left out: it describes the agent
            # right now, which says nothing about a period that already closed.
            thumbnail: agent.avatar_url,
            calls_answered: answered[id].to_i,
            outbound_calls: outbound[id].to_i,
            missed_calls: missed,
            response_rate: response_rate(taken, missed),
            avg_time_to_answer: round_seconds(answer_time[id]),
            call_minutes: to_minutes(minutes[id]),
            outbound_call_minutes: to_minutes(outbound_minutes[id]),
            avg_outbound_duration: round_seconds(outbound_avg[id]),
            notes: notes[id].to_i,
            resolved_conversations: resolved[id].to_i
          }
        end

        rows + unattributed_rows(rows)
      end

      # Work on call conversations that no agent row can claim, so the per-agent
      # figures add up to the inbox ones instead of quietly losing a couple of
      # rows. The common case is a call nobody answered: no agent ever joined,
      # so the conversation was never assigned, and somebody closed it from the
      # unassigned list later.
      #
      # Taken as total minus attributed rather than by looking for a null
      # assignee, so it also catches work credited to somebody who is not a
      # member of these inboxes and so has no row of their own.
      def unattributed_rows(rows)
        resolved_gap = resolved_conversations.count - rows.sum { |r| r[:resolved_conversations] }
        notes_gap = private_notes.count - rows.sum { |r| r[:notes] }
        return [] if resolved_gap <= 0 && notes_gap <= 0

        # A nil id marks the row as not being an agent: the frontend labels it
        # and skips the avatar. Metrics that only mean something for an agent
        # stay nil so they render blank instead of as a misleading zero.
        [{
          id: nil,
          name: nil,
          email: nil,
          thumbnail: nil,
          calls_answered: nil,
          outbound_calls: nil,
          missed_calls: nil,
          response_rate: nil,
          avg_time_to_answer: nil,
          call_minutes: nil,
          outbound_call_minutes: nil,
          avg_outbound_duration: nil,
          notes: [notes_gap, 0].max,
          resolved_conversations: [resolved_gap, 0].max
        }]
      end

      # Agents who can take calls on the inboxes in scope, so someone who
      # answered nothing in the period still shows up as a row of zeros —
      # that absence is what a supervisor is looking for.
      #
      # Read through inboxes, which is scoped to the account, rather than from
      # the requested inbox_id directly: inbox_members carries no account_id,
      # so a raw id would return whoever belongs to that inbox whatever tenant
      # it is in, and this roster holds names and emails.
      #
      # Selected through a subquery rather than a join with DISTINCT: users
      # carries json columns, which Postgres cannot compare for equality.
      def agents
        @agents ||= ::User.where(
          id: ::InboxMember.where(inbox_id: inboxes.select(:id)).select(:user_id)
        ).order(:name)
      end

      # ---------- by inbox ----------

      def rows_by_inbox
        answered = calls.incoming.answered.group(:inbox_id).count
        unattended = unattended_calls.group(:inbox_id).count
        outbound = calls.outgoing.group(:inbox_id).count
        minutes = calls.answered.group(:inbox_id).sum(:duration_seconds)
        outbound_minutes = calls.outgoing.group(:inbox_id).sum(:duration_seconds)
        outbound_avg = calls.outgoing.group(:inbox_id).average(:duration_seconds)
        answer_time = answered_incoming_calls.group(:inbox_id).average(CUSTOMER_WAIT_SQL)
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
