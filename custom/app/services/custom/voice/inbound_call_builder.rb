# frozen_string_literal: true

module Custom
  module Voice
    class InboundCallBuilder
      # How recently the conversation has to have moved for its owner to still
      # count as the person handling this customer.
      ASSIGNEE_PREFERENCE_WINDOW = 30.minutes

      attr_reader :inbox, :call_sid, :provider, :extra_meta, :source_ids, :contact_attributes

      def self.perform!(inbox:, call_sid:, caller:, provider: :twilio, extra_meta: {})
        new(inbox: inbox, call_sid: call_sid, caller: caller, provider: provider, extra_meta: extra_meta).perform!
      end

      def initialize(inbox:, call_sid:, caller:, provider: :twilio, extra_meta: {})
        @inbox = inbox
        @call_sid = call_sid
        @provider = provider.to_sym
        @extra_meta = extra_meta || {}
        @source_ids = Array(caller[:source_ids]).compact_blank
        @contact_attributes = caller[:contact_attributes] || {}
      end

      def perform!
        existing = find_existing_call
        return existing if existing

        call = ActiveRecord::Base.transaction do
          contact_inbox = ensure_contact_inbox!
          contact = contact_inbox.contact
          conversation = resolve_conversation!(contact, contact_inbox)
          call = create_call!(contact, conversation)
          assign_initial_ring_agent!(call)
          message = Custom::Voice::CallMessageBuilder.new(call).perform!
          call.update!(message_id: message.id)
          call
        end

        schedule_ring_timeout!(call)
        call
      rescue ActiveRecord::RecordNotUnique
        find_existing_call || raise
      end

      private

      def account
        inbox.account
      end

      def find_existing_call
        Custom::Call.where(account_id: account.id, inbox_id: inbox.id)
                    .find_by(provider: provider, provider_call_id: call_sid)
      end

      def ensure_contact_inbox!
        ContactInboxSourceIdResolver.new(
          inbox: inbox, source_ids: source_ids, contact_attributes: contact_attributes
        ).perform
      end

      # Records on the call whether this call is what brought the conversation
      # into being, which is what decides who ends up owning it. See
      # Custom::Call#assign_conversation_to!.
      def resolve_conversation!(contact, contact_inbox)
        reusable = if inbox.lock_to_single_conversation
                     contact_inbox.conversations.last
                   else
                     contact_inbox.conversations.where.not(status: :resolved).last
                   end
        return reusable if reusable

        @conversation_created = true
        account.conversations.create!(
          contact_inbox_id: contact_inbox.id,
          inbox_id: inbox.id,
          contact_id: contact.id,
          status: :open
        )
      end

      def create_call!(contact, conversation)
        call = Custom::Call.create!(
          account: account,
          inbox: inbox,
          conversation: conversation,
          contact: contact,
          provider: provider,
          direction: :incoming,
          status: 'ringing',
          provider_call_id: call_sid,
          meta: { 'initiated_at' => Time.zone.now.to_i, 'conversation_created' => @conversation_created.present? }
                  .merge(extra_meta.stringify_keys)
        )
        call.update!(conference_sid: call.default_conference_sid) if call.twilio?
        call
      end

      def assign_initial_ring_agent!(call)
        agent = Custom::Voice::CallRouter.new(inbox: inbox, preferred_agent_id: preferred_agent_id(call)).next_agent
        return unless agent

        call.update!(
          current_ring_agent_id: agent.id,
          meta: call.meta.merge('rang_agent_ids' => [agent.id])
        )
        Custom::Voice::RingAttemptTracker.open!(call, agent.id)
        call.broadcast_voice_call_event(:ring_reassigned, previous_agent_id: nil)
      end

      # The agent already working this thread gets the first turn, so a customer
      # who was just chatting with somebody reaches that same somebody instead of
      # whoever the round robin happens to favour.
      #
      # Only for a conversation that already existed. One this call created has
      # an owner stamped by Chatwoot's inbox auto-assignment moments earlier,
      # chosen by its own round robin and meaning nothing here — preferring that
      # would just be a second, worse round robin. See
      # Custom::Call#assign_conversation_to!.
      #
      # A stale thread does not count as context either: an owner from last week
      # is somebody who has long since moved on, and holding the first turn for
      # them only makes the caller wait out the ring timeout.
      def preferred_agent_id(call)
        return if call.conversation_created

        conversation = call.conversation
        return unless conversation.open?
        return unless conversation.last_activity_at > ASSIGNEE_PREFERENCE_WINDOW.ago

        conversation.assignee_id
      end

      # Always arm the timeout job, even with no agent to ring: the caller waits
      # until max_wait either way, and only this job expires the call.
      def schedule_ring_timeout!(call)
        call.broadcast_voice_call_event(:unassigned) if call.current_ring_agent_id.nil?

        Custom::Voice::CallRingTimeoutJob
          .set(wait: inbox.channel.ring_timeout_seconds.seconds)
          .perform_later(call.id, call.current_ring_agent_id)
      end
    end
  end
end
