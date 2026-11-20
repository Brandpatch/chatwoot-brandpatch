# frozen_string_literal: true

module Custom
  module Voice
    # A caller who hangs up while the language menu is still playing is never
    # offered to anybody: the call is closed as missed with no ring turn, and its
    # conversation stays unassigned with nothing to say why it exists. The team
    # finds it among the unassigned ones and calls back by hand.
    #
    # This gives that conversation an owner, an online member of the inbox taken
    # in rotation, and a private note that says what happened. It does not open a
    # ring turn: the per-agent missed-call reports are built from those turns,
    # and nobody here was offered a call.
    #
    # A conversation that already has an owner keeps it and only gets the note.
    class LanguageMenuHangupFollowUp
      pattr_initialize [:call!]

      def perform
        return unless left_in_language_menu?

        conversation = call.conversation
        assign_to_online_agent!(conversation) if conversation.assigned_entity.blank?
        add_note!(conversation)
      end

      private

      # routing_deferred is only ever cleared once an agent has been reserved, so
      # a call that still has it when it ends never got past the menu. A
      # provider failure is not a caller giving up.
      def left_in_language_menu?
        call.incoming? && call.routing_deferred? && %w[completed no_answer].include?(call.status)
      end

      def assign_to_online_agent!(conversation)
        agent = Custom::Voice::CallRouter.new(inbox: call.inbox).follow_up_agent
        return unless agent

        ::Conversations::AssignmentService.new(conversation: conversation, assignee_id: agent.id).perform
        call.update!(meta: call.meta.merge('follow_up_agent_id' => agent.id))
      end

      def add_note!(conversation)
        note = I18n.t('conversations.voice.language_menu_hangup_note', locale: call.account.locale)
        Messages::MessageBuilder.new(nil, conversation, { content: note, private: true }).perform
      end
    end
  end
end
