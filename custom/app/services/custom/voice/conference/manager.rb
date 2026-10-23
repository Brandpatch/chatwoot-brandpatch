# frozen_string_literal: true

module Custom
  module Voice
    module Conference
      class Manager
        pattr_initialize [:call!, :event!, :participant_label]

        AGENT_LABEL_PATTERN = /\Aagent-(\d+)-account-(\d+)\z/

        def process
          case event
          when 'start'
            mark_ringing!
          when 'join'
            agent_participant? ? join_agent! : caller_presence.record_join!
          when 'leave'
            handle_leave!
            assign_waiting_calls! if agent_participant?
          when 'end'
            finalize!
          end
        end

        private

        def status_manager
          @status_manager ||= Custom::Voice::CallStatus::Manager.new(call: call)
        end

        def caller_presence
          @caller_presence ||= Custom::Voice::CallerPresence.new(call: call)
        end

        # The caller gave up before the agent got in, so nobody is waiting on the
        # other side and nobody answered. no_answer is terminal and unanswered,
        # which is exactly what the inbox's unattended column counts, and the
        # open ring turn closes as caller_hangup — not one of MISSED_OUTCOMES —
        # so the agent is credited with neither an answer nor a miss.
        #
        # Claiming is skipped entirely rather than undone: accepted_by_agent_id,
        # the answered turn and the conversation assignment all follow from the
        # claim, and writing then reverting them would broadcast an accepted
        # call to the agent's widget on the way past.
        #
        # Ending the conference is what the agent actually feels: without it
        # they sit in an empty room on hold music, which is the ringing the
        # report described. Their leg is the only one left, so completing the
        # conference drops them out.
        def abandon_empty_conference!
          Rails.logger.info("VOICE_CALLER_ABSENT: call=#{call.id} conference=#{call.conference_sid}")
          status_manager.process_status_update('no_answer', timestamp: now)
          Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
        end

        def mark_ringing!
          return unless call.status == 'ringing'

          status_manager.process_status_update('ringing')
        end

        def join_agent!
          user_id = extract_user_id
          return unless user_id
          return abandon_empty_conference! if caller_presence.absent?

          claim_for_user!(user_id)
          # Inbound only. There the caller is already in the conference, so the
          # agent arriving is the moment the two are together. An outbound call
          # is the other way round: the agent's browser joins while the
          # customer's phone is still ringing, and calling that 'in progress'
          # credits a conversation that may never happen. The agent then hangs
          # up on the ringing, finds the call already in_progress and writes
          # 'completed' over it with a duration counted from their own join;
          # Twilio's 'canceled' for the customer leg arrives afterwards and is
          # ignored, because the first terminal status wins.
          #
          # Measured in production: 331 outbound calls the customer never
          # picked up were stored as answered, carrying 314 minutes of talk
          # time nobody spoke into the per-agent report. What actually connects
          # an outbound call is the customer answering, and their leg's status
          # callback already reports that as 'answered'.
          status_manager.process_status_update('in_progress', timestamp: now) if call.incoming?
          return unless call.accepted_by_agent_id == user_id && mark_accepted_broadcast!

          call.broadcast_voice_call_event(:accepted, accepted_by_agent_id: call.accepted_by_agent_id)
        end

        def claim_for_user!(user_id)
          claimed = false
          call.with_lock do
            next if call.terminal? || (call.accepted_by_agent_id.present? && call.accepted_by_agent_id != user_id)

            call.update!(accepted_by_agent_id: user_id) if call.accepted_by_agent_id != user_id
            claimed = true
          end

          return unless claimed

          Custom::Voice::RingAttemptTracker.record_answer!(call, user_id)
          call.assign_conversation_to!(user_id)
        end

        def mark_accepted_broadcast!
          first_time = false
          call.with_lock do
            next if call.terminal? || call.accepted_broadcast_at.present?

            call.update!(accepted_broadcast_at: now)
            first_time = true
          end
          first_time
        end

        def extract_user_id
          match = participant_label.to_s.match(AGENT_LABEL_PATTERN)
          return unless match
          return unless match[2].to_i == call.account_id

          match[1].to_i
        end

        def handle_leave!
          case call.status
          when 'ringing'
            status_manager.process_status_update('no_answer', timestamp: now)
          when 'in_progress'
            # The participant label is the only place in the whole flow where a
            # connected call ending can be attributed without guessing: both
            # sides leaving arrive here as the same 'completed'.
            reason = agent_participant? ? Custom::Call::AGENT_HANGUP : Custom::Call::CALLER_HANGUP
            status_manager.process_status_update('completed', timestamp: now, end_reason: reason)
          end
        end

        def finalize!
          return if Custom::Call::TERMINAL_STATUSES.include?(call.status)

          status_manager.process_status_update('completed', timestamp: now)
        end

        def agent_participant?
          participant_label.to_s.start_with?('agent-')
        end

        def now
          Time.zone.now.to_i
        end

        def assign_waiting_calls!
          call.reload
          return unless call.terminal?

          # Incoming only. An outbound call sits at 'ringing' with no ring agent
          # from the moment it is placed until the customer picks up, so without
          # this filter every agent hanging up on this inbox handed somebody
          # else's outbound call to a stranger: 491 of 5.704 outbound calls over
          # 21 days, 478 of them rung to an agent other than the one dialling.
          # It also dragged them into the inbound lifecycle — 85 ended labelled
          # no_answer on calls the customer had answered — and doubled the odds
          # of nobody reaching the conference at all, 11,2% against 3,9%.
          #
          # An outbound call already has its agent: whoever placed it.
          Custom::Call
            .where(inbox_id: call.inbox_id, direction: :incoming, status: 'ringing', current_ring_agent_id: nil)
            .where.not(id: call.id)
            .order(created_at: :asc)
            .each { |waiting| assign_waiting_call!(waiting) }
        end

        # The call lock this used to take guarded the wrong thing: it stopped two
        # writers touching the same call, while the collision was two calls
        # taking the same agent. reserve_for! locks the account instead.
        def assign_waiting_call!(waiting)
          rang_ids = Array(waiting.meta['rang_agent_ids']).map(&:to_i)
          agent = Custom::Voice::CallRouter
                  .new(inbox: waiting.inbox, exclude_agent_ids: rang_ids)
                  .reserve_for!(waiting)
          return unless agent

          Custom::Voice::RingAttemptTracker.open!(waiting, agent.id)

          waiting.broadcast_voice_call_event(:ring_reassigned,
                                             previous_agent_id: nil,
                                             current_ring_agent_id: agent.id)

          Custom::Voice::CallRingTimeoutJob
            .set(wait: waiting.inbox.channel.ring_timeout_seconds.seconds)
            .perform_later(waiting.id, agent.id)
        end
      end
    end
  end
end
