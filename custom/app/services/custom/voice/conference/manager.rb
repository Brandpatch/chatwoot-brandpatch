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
            join_agent! if agent_participant?
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

        def mark_ringing!
          return unless call.status == 'ringing'

          status_manager.process_status_update('ringing')
        end

        def join_agent!
          user_id = extract_user_id
          return unless user_id

          claim_for_user!(user_id)
          status_manager.process_status_update('in_progress', timestamp: now)
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

          Custom::Voice::RingAttemptTracker.close!(call, Custom::CallRingAttempt::ANSWERED,
                                                   agent_id: user_id)
          auto_assign_conversation!(user_id)
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

        def auto_assign_conversation!(user_id)
          conversation = call.conversation
          return if conversation.assigned_entity.present?

          Conversations::AssignmentService.new(conversation: conversation, assignee_id: user_id).perform
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
            status_manager.process_status_update('completed', timestamp: now)
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

          Custom::Call
            .where(inbox_id: call.inbox_id, status: 'ringing', current_ring_agent_id: nil)
            .where.not(id: call.id)
            .order(created_at: :asc)
            .each { |waiting| assign_waiting_call!(waiting) }
        end

        def assign_waiting_call!(waiting)
          rang_ids = Array(waiting.meta['rang_agent_ids']).map(&:to_i)
          agent = Custom::Voice::CallRouter.new(inbox: waiting.inbox, exclude_agent_ids: rang_ids).next_agent
          return unless agent

          assigned = false
          waiting.with_lock do
            next unless waiting.status == 'ringing' && waiting.current_ring_agent_id.nil?

            waiting.update!(
              current_ring_agent_id: agent.id,
              meta: waiting.meta.merge('rang_agent_ids' => rang_ids | [agent.id])
            )
            assigned = true
          end

          return unless assigned

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
