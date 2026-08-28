# frozen_string_literal: true

module Custom
  module Voice
    class InboundCallBuilder
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

        ActiveRecord::Base.transaction do
          contact_inbox = ensure_contact_inbox!
          contact = contact_inbox.contact
          conversation = resolve_conversation!(contact, contact_inbox)
          call = create_call!(contact, conversation)
          message = Custom::Voice::CallMessageBuilder.new(call).perform!
          call.update!(message_id: message.id)
          call
        end
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

      def resolve_conversation!(contact, contact_inbox)
        reusable = if inbox.lock_to_single_conversation
                     contact_inbox.conversations.last
                   else
                     contact_inbox.conversations.where.not(status: :resolved).last
                   end
        return reusable if reusable

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
          meta: { 'initiated_at' => Time.zone.now.to_i }.merge(extra_meta.stringify_keys)
        )
        call.update!(conference_sid: call.default_conference_sid) if call.twilio?
        call
      end
    end
  end
end
