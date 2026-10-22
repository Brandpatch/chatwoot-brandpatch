# frozen_string_literal: true

# Answers whether the customer is actually on an inbound call before an agent is
# credited with taking it.
#
# Inbound calls carry no terminal status callback for the customer's leg: the
# number-level StatusCallback only reports outbound progress, so a caller who
# hangs up while the phone is ringing leaves no trace. Measured over two hours of
# production webhooks, 1.830 of 1.849 status callbacks were outbound-api and the
# remaining 19 were agent legs — not one customer leg. The call therefore stays
# 'ringing', an agent is offered it, and they land in a conference nobody else
# ever joined.
#
# Measured in production: of 60 sampled inbound calls stored as answered and
# ended by the agent, 4 had a customer leg Twilio reported as no-answer with
# duration 0 — around 239 of that subset, 1,9% of answered inbound calls. They
# count as answered in the reports and carry talk time nobody spoke into.
#
# The customer joins the conference before the agent is rung, so their
# participant-join is recorded as it arrives and answers this for free. The
# provider is only consulted when that record is missing, which is either the
# bug or a callback that has not landed yet — and only the provider can tell
# those apart. Fails open on every unknown: the bug costs an empty room, while a
# wrong 'absent' would hang up on a real conversation.
module Custom
  module Voice
    class CallerPresence
      CONTACT_LABEL = 'contact'
      LIVE_CONFERENCE_STATUS = 'in-progress'

      pattr_initialize [:call!]

      def self.absent?(call)
        new(call: call).absent?
      end

      # Outbound calls are not in question here: there the agent joins first by
      # design and Conference::Manager already withholds 'in_progress' until the
      # customer's own leg reports answering.
      def absent?
        return false unless call.incoming?
        return false if joined_at.present?

        confirmed_absent?
      end

      # Stamped from the customer's participant-join so the common case never
      # reaches the provider. Idempotent: a second join (a reconnect) keeps the
      # first arrival, which is the one that proves they were there.
      def record_join!
        return if joined_at.present?

        call.update!(meta: call.meta.merge('caller_joined_at' => Time.zone.now.to_i))
      end

      private

      def joined_at
        call.meta['caller_joined_at']
      end

      # Two ways to be sure the customer is gone: the conference holds every
      # participant but them, or there is no live conference at all — which is
      # the shape of this bug, since an inbound caller is put into the conference
      # the moment they arrive and long before any agent is offered the call.
      #
      # Looked up by friendly_name rather than the provider's own SID because
      # that SID reaches us through the very callbacks this bug lacks, while the
      # friendly name is ours and known from the start.
      def confirmed_absent?
        return false if call.conference_sid.blank?

        conferences = client.conferences.list(friendly_name: call.conference_sid, status: LIVE_CONFERENCE_STATUS)
        return true if conferences.empty?

        conferences.none? { |conference| contact_among?(conference) }
      # TwilioError is the base RestError inherits from, so one rescue covers a
      # rejected request and a transport failure alike. Both mean the same thing
      # here: we did not find out, so we do not act.
      rescue ::Twilio::REST::TwilioError => e
        Rails.logger.info("VOICE_CALLER_PRESENCE_UNKNOWN: call=#{call.id} conference=#{call.conference_sid} #{e.message}")
        false
      end

      def contact_among?(conference)
        client.conferences(conference.sid).participants.list.any? { |participant| participant.label == CONTACT_LABEL }
      end

      def client
        @client ||= call.inbox.channel.client
      end
    end
  end
end
