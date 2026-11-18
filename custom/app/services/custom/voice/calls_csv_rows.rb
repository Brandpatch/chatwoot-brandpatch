# frozen_string_literal: true

module Custom
  module Voice
    # The rows of the calls CSV, read as plain columns instead of as Calls.
    #
    # Building a Call for every row, with its contact, agent, inbox, channel and
    # conversation, is what made a month of calls take longer than the 15 seconds
    # the server gives a request: 27.500 rows took 12 s in production before any
    # of the file was written. The export needs a dozen values per call, so it
    # asks the database for exactly those and looks the few things that repeat
    # (inboxes, agents) up once.
    #
    # Keyset paging on the primary key, newest first, which is the order the list
    # shows. A call's row is written when the call starts, so ids and start times
    # run together.
    class CallsCsvRows
      include Enumerable

      Row = Struct.new(:created_at, :kind, :direction, :from_number, :to_number, :contact_name, :agent_name,
                       :duration_seconds, :inbox_name, :conversation_id, :language, :missed_reason)

      CALL_COLUMNS = [:id, :created_at, :status, :direction, :duration_seconds, :accepted_by_agent_id,
                      :inbox_id, :conversation_id, :contact_id, Arel.sql("calls.meta->>'language'"),
                      Arel.sql("calls.meta->>'caller_id'")].freeze

      def initialize(calls, batch_size:)
        @calls = calls
        @batch_size = batch_size
        @inboxes = {}
        @agent_names = {}
      end

      def each(&)
        last_id = nil
        loop do
          page = @calls.reorder(id: :desc).limit(@batch_size)
          page = page.where('calls.id < ?', last_id) if last_id
          calls = page.pluck(*CALL_COLUMNS)
          break if calls.empty?

          rows_for(calls).each(&)
          last_id = calls.last.first
        end
      end

      private

      def rows_for(calls)
        contacts = ::Contact.where(id: calls.map { |call| call[8] }.uniq).pluck(:id, :name, :phone_number).index_by(&:first)
        conversations = ::Conversation.where(id: calls.map { |call| call[7] }.uniq).pluck(:id, :display_id).to_h
        load_inboxes(calls.map { |call| call[6] })
        turns = turns_of_missed(calls)
        load_agent_names(calls.filter_map { |call| call[5] } + turns.values.flatten(1).map { |turn| turn[1] })

        calls.map do |id, created_at, status, direction, duration, agent_id, inbox_id, conversation_id, contact_id, language, caller_id|
          kind = Custom::Call.kind_for(status: status, direction: direction, accepted_by_agent_id: agent_id)
          inbox_name, inbox_phone = @inboxes[inbox_id]
          contact_name, contact_phone = contacts[contact_id]&.drop(1)
          incoming = direction == 'incoming'
          missed_turns = turns[id]

          # An outbound call keeps the number the customer saw, as Call#from_number does.
          Row.new(created_at, kind, direction, incoming ? contact_phone : (caller_id.presence || inbox_phone), incoming ? inbox_phone : contact_phone,
                  contact_name, agent_name_for(kind, agent_id, missed_turns), duration, inbox_name, conversations[conversation_id],
                  language, kind == 'missed' ? missed_reason_for(missed_turns) : nil)
        end
      end

      # The ring turns of the calls that went unattended, which are what the
      # reason and the agent column of those rows are read from. Calls with no
      # turn at all are in the result too, as empty lists.
      def turns_of_missed(calls)
        missed_ids = calls.filter_map do |id, _, status, direction, _, agent_id|
          id if Custom::Call.kind_for(status: status, direction: direction, accepted_by_agent_id: agent_id) == 'missed'
        end
        turns = Custom::CallRingAttempt.where(call_id: missed_ids).order(:rang_at).pluck(:call_id, :agent_id, :outcome).group_by(&:first)
        missed_ids.index_with { |id| turns.fetch(id, []) }
      end

      # On a missed call the agent is not accepted_by_agent, which a missed call
      # never has: it is the agents whose turn timed out or was declined, the same
      # ones the reports hold the miss against. A caller who hung up while it rang
      # is nobody's miss, so those rows carry a reason and no agent even though
      # the call did ring somebody.
      def agent_name_for(kind, agent_id, missed_turns)
        return @agent_names[agent_id] unless kind == 'missed'

        missed_turns.select { |_, _, outcome| Custom::CallRingAttempt::MISSED_OUTCOMES.include?(outcome) }
                    .map { |_, turn_agent_id, _| @agent_names[turn_agent_id] }.uniq.join(', ')
      end

      # Why nobody took an inbound call, read off its ring turns. The order
      # matters: an agent who did not answer or declined is the most specific
      # answer, and a caller who hung up while it rang is what is left when no turn
      # was the agent's to decide. A call with no turns at all never reached an
      # agent: nobody was online and free, or the account was paused, and the call
      # keeps no trace of which.
      def missed_reason_for(turns)
        outcomes = turns.map(&:last)
        return 'no_agents_available' if outcomes.empty?
        return 'agent_no_answer' if outcomes.include?(Custom::CallRingAttempt::TIMEOUT)
        return 'agent_rejected' if outcomes.include?(Custom::CallRingAttempt::REJECTED)

        'caller_hung_up'
      end

      def load_inboxes(ids)
        missing = ids.uniq - @inboxes.keys
        return if missing.empty?

        ::Inbox.where(id: missing).includes(:channel).each { |inbox| @inboxes[inbox.id] = [inbox.name, inbox.channel&.phone_number] }
      end

      def load_agent_names(ids)
        missing = ids.uniq - @agent_names.keys
        return if missing.empty?

        ::User.where(id: missing).each { |user| @agent_names[user.id] = user.available_name }
      end
    end
  end
end
