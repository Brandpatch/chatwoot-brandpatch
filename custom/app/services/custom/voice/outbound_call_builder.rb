# frozen_string_literal: true

module Custom
  module Voice
    class OutboundCallBuilder
      attr_reader :account, :inbox, :user, :contact

      def self.perform!(**)
        new(**).perform!
      end

      # dialer is given only by the auto-dialer, which builds the call before
      # its customer is dialled: the agent joins first, and the dial happens on
      # their participant-join. Until then there is no Twilio SID, so the call
      # takes a placeholder for good. See Custom::Call#dialer?.
      def initialize(account:, inbox:, user:, contact:, conversation: nil, dialer: nil) # rubocop:disable Metrics/ParameterLists
        @account = account
        @inbox = inbox
        @user = user
        @contact = contact
        @existing_conversation = conversation
        @dialer = dialer
      end

      def perform!
        raise ArgumentError, 'Contact phone number required' if contact.phone_number.blank?
        raise ArgumentError, 'Agent required' if user.blank?

        claim_for_caller = @existing_conversation && @existing_conversation.assigned_entity.nil?

        ActiveRecord::Base.transaction do
          contact_inbox = ensure_contact_inbox!
          conversation = @existing_conversation || create_conversation!(contact_inbox)
          call_sid = @dialer ? "dialer-#{SecureRandom.uuid}" : initiate_call!
          if claim_for_caller
            @existing_conversation.lock!
            @existing_conversation.update!(assignee: user)
          end
          call = create_call!(conversation, call_sid)
          message = Custom::Voice::CallMessageBuilder.new(call).perform!
          call.update!(message_id: message.id)
          call
        end
      end

      private

      def ensure_contact_inbox!
        ContactInbox.find_or_create_by!(
          contact_id: contact.id,
          inbox_id: inbox.id
        ) do |record|
          record.source_id = contact.phone_number
        end
      end

      def create_conversation!(contact_inbox)
        account.conversations.create!(
          contact_inbox_id: contact_inbox.id,
          inbox_id: inbox.id,
          contact_id: contact.id,
          assignee_id: user.id,
          status: :open
        )
      end

      def initiate_call!
        inbox.channel.initiate_call(to: contact.phone_number)[:call_sid]
      end

      def create_call!(conversation, call_sid)
        call = Custom::Call.create!(
          account: account,
          inbox: inbox,
          conversation: conversation,
          contact: contact,
          accepted_by_agent: user,
          provider: :twilio,
          direction: :outgoing,
          status: 'ringing',
          provider_call_id: call_sid,
          meta: { 'initiated_at' => Time.zone.now.to_i, 'dialer' => @dialer }.compact
        )
        call.update!(conference_sid: call.default_conference_sid)
        call
      end
    end
  end
end
