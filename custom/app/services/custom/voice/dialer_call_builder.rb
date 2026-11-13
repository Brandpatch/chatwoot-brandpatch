# frozen_string_literal: true

# Places one auto-dialer call: reserves a free agent, builds the contact,
# conversation and call around them, and leaves the customer undialled. The
# agent's browser joins on its own when the assignment reaches it, and the
# customer is dialled from that join (Custom::Voice::DialerCustomerLeg), so a
# customer who picks up always finds an agent already there.
module Custom
  module Voice
    class DialerCallBuilder
      # Long enough for a browser to fetch a token, register the Device and
      # connect; short enough that an agent whose tab never answers is back in
      # rotation before the next lead is due.
      AGENT_JOIN_TIMEOUT = 15.seconds

      pattr_initialize [:inbox!, :requester!, :phone_number!, :external_id!, :name, :note, { metadata: {} }]

      def perform!
        call = Custom::Voice::CallRouter.new(inbox: inbox).reserve_for_dialer! { |agent| build_call!(agent) }

        Custom::Voice::DialerAgentJoinTimeoutJob.set(wait: AGENT_JOIN_TIMEOUT).perform_later(call.id)
        # To the agent's own stream rather than the account's: the payload
        # carries the lead's note, and the account stream reaches every agent.
        ActionCable.server.broadcast(
          call.accepted_by_agent.pubsub_token,
          call.voice_call_event_payload(:dialer_call_assigned, agent_id: call.accepted_by_agent_id, note: note)
        )
        call
      end

      private

      # Runs under the reservation lock, which is also what makes the duplicate
      # check below race-free: every dialer call of the account is created
      # behind it.
      def build_call!(agent)
        raise Custom::Voice::CallRouter::DialerUnavailable, 'already_in_progress' if already_in_progress?

        contact_inbox = resolve_contact_inbox!
        call = Custom::Voice::OutboundCallBuilder.perform!(
          account: inbox.account, inbox: inbox, user: agent, contact: contact_inbox.contact,
          conversation: contact_inbox.conversations.open.last,
          dialer: { 'external_id' => external_id, 'phase' => 'awaiting_agent', 'requested_at' => Time.zone.now.to_i, 'metadata' => metadata }
        )
        add_note!(call.conversation) if note.present?
        call
      end

      def already_in_progress?
        Custom::Call.active.where(account_id: inbox.account_id).exists?(["meta -> 'dialer' ->> 'external_id' = ?", external_id])
      end

      def resolve_contact_inbox!
        ContactInboxSourceIdResolver.new(
          inbox: inbox, source_ids: [phone_number], contact_attributes: { name: name.presence || phone_number, phone_number: phone_number }
        ).perform
      end

      # Written as the integration user who asked for the call, the same way a
      # note posted through the API would be.
      def add_note!(conversation)
        Messages::MessageBuilder.new(requester, conversation, { content: note, private: true }).perform
      end
    end
  end
end
