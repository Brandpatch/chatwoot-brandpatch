# frozen_string_literal: true

module Custom
  module Twilio
    class VoiceController < ApplicationController
      CONFERENCE_EVENT_PATTERNS = {
        /conference-start/i => 'start',
        /participant-join/i  => 'join',
        /participant-leave/i => 'leave',
        /conference-end/i    => 'end'
      }.freeze

      # Twilio's own TwiML pronunciation for the two the account supports
      # today. Kept short on purpose: every second of audio here is time the
      # caller waits before anyone can be rung, on top of however long they
      # already waited in queue.
      LANGUAGE_PROMPT = 'Para español, marque 1. For English, press 2.'
      LANGUAGE_GATHER_TIMEOUT = 3

      skip_before_action :verify_authenticity_token, raise: false
      before_action :set_inbox!
      before_action :verify_twilio_signature!

      def status
        Custom::Voice::StatusUpdateService.new(
          account: current_account,
          call_sid: twilio_call_sid,
          call_status: params[:CallStatus],
          payload: params.to_unsafe_h
        ).perform
        head :no_content
      end

      def call_twiml
        Rails.logger.info(
          "CUSTOM_TWILIO_VOICE_TWIML account=#{current_account.id} call_sid=#{twilio_call_sid} " \
          "from=#{twilio_from} direction=#{twilio_direction}"
        )
        return render xml: reject_twiml if reject_inbound?

        call = resolve_call
        return render xml: hangup_twiml if joining_a_dead_call?(call)
        return render xml: language_menu_twiml if show_language_menu?(call)

        render xml: conference_twiml(call)
      end

      # The caller picked a language (or let both prompts time out — see
      # language_menu_twiml). Only reachable for a call InboundCallBuilder
      # created with defer_routing: true, so nobody rings before this runs.
      def language
        call = find_call_for_language!
        call.update!(language: params[:Digits] == '2' ? 'en' : 'es')
        Custom::Voice::InboundCallBuilder.continue_routing!(call)
        render xml: conference_twiml(call)
      end

      def conference_status
        event = mapped_conference_event
        if event.nil?
          Rails.logger.info(
            "CUSTOM_TWILIO_VOICE_CONFERENCE_UNMAPPED_EVENT account=#{current_account.id} " \
            "event=#{params[:StatusCallbackEvent]} call_sid=#{twilio_call_sid}"
          )
          return head :no_content
        end

        call = find_call_for_conference!(params[:FriendlyName], twilio_call_sid)
        persist_twilio_conference_sid!(call, params[:ConferenceSid])

        Custom::Voice::Conference::Manager.new(
          call: call,
          event: event,
          participant_label: participant_label
        ).process

        head :no_content
      end

      def recording_status
        Custom::Voice::RecordingStatusService.new(
          account: current_account,
          payload: params.to_unsafe_h
        ).perform
        head :no_content
      end

      private

      def twilio_call_sid
        params[:CallSid]
      end

      def twilio_from
        params[:From].to_s
      end

      def twilio_direction
        @twilio_direction ||= (params['Direction'] || params['CallDirection']).to_s
      end

      def mapped_conference_event
        event = params[:StatusCallbackEvent].to_s
        CONFERENCE_EVENT_PATTERNS.each do |pattern, mapped|
          return mapped if event.match?(pattern)
        end
        nil
      end

      def agent_leg?(from_number)
        from_number.start_with?('client:')
      end

      def reject_inbound?
        twilio_direction == 'inbound' && !agent_leg?(twilio_from) && !inbox.channel.inbound_calls_enabled?
      end

      def reject_twiml
        ::Twilio::TwiML::VoiceResponse.new(&:reject).to_s
      end

      # The agent dials in on a leg of their own, and it asks for this TwiML
      # after the customer's leg may already have died — measured at 506ms past
      # the webhook that ended the call. Sending them into the conference then
      # left them alone with hold music and no card to hang up from: the widget
      # had closed on that same status update.
      #
      # Answered here rather than by tearing the conference down from the status
      # webhook because the agent is the one who starts it
      # (start_conference_on_enter), so at webhook time there is often no
      # conference to close yet. By the time this request arrives the outcome is
      # already recorded, so there is no race left to lose.
      #
      # Outbound only, and only a call this agent has not already been part of.
      # started_at is stamped when a participant joins the conference, not when
      # the customer picks up — Conference::Manager#join_agent! is its only
      # writer — so a call that has one is a call whose conference this agent
      # already entered, and rejoining it is legitimate: a reconnect after a
      # dropped socket, a second tab. Only a call that died before they ever got
      # in is the one with nothing to come back to.
      #
      # That makes this narrow on purpose: measured over five failed calls, four
      # had already been joined once and only one was caught here. The frontend
      # check in joinCall is what stops most of them, before the leg is even
      # dialled; this is the backstop for the ordering the frontend cannot see,
      # where the provider reports the death after the agent's leg is already on
      # its way (measured at 506ms).
      def joining_a_dead_call?(call)
        return false unless agent_leg?(twilio_from)
        return false unless call.outgoing?

        call.terminal? && call.started_at.blank?
      end

      def hangup_twiml
        ::Twilio::TwiML::VoiceResponse.new(&:hangup).to_s
      end

      # Explicit agent_leg?/incoming? checks rather than trusting
      # routing_deferred? alone: assign_initial_ring_agent! broadcasts the
      # ring to the agent's browser before it flips that flag off, so without
      # this an agent's own leg could, in that narrow window, be asked to sit
      # through the menu instead of entering the conference. Outbound calls
      # never carry the flag at all — only InboundCallBuilder sets it — but
      # checking incoming? here keeps that explicit rather than incidental.
      def show_language_menu?(call)
        return false if agent_leg?(twilio_from)
        return false unless call.incoming?

        call.routing_deferred?
      end

      def resolve_call
        return find_call_for_agent if agent_leg?(twilio_from)

        case twilio_direction
        when 'inbound'
          Custom::Voice::InboundCallBuilder.perform!(
            inbox: inbox,
            call_sid: twilio_call_sid,
            caller: { source_ids: [twilio_from], contact_attributes: { name: twilio_from, phone_number: twilio_from } },
            defer_routing: inbox.channel.voice_language_menu_enabled?
          )
        when 'outbound-api', 'outbound-dial'
          sync_outbound_leg(call_sid: twilio_call_sid, direction: twilio_direction)
        else
          raise ArgumentError, "Unsupported Twilio direction: #{twilio_direction}"
        end
      end

      def find_call_for_agent
        sid = params[:call_sid].presence
        raise ArgumentError, 'call_sid is required for agent leg' if sid.blank?

        inbox_calls.find_by!(provider_call_id: sid)
      end

      def sync_outbound_leg(call_sid:, direction:)
        parent_sid = params['ParentCallSid'].presence
        lookup_sid = direction == 'outbound-dial' ? parent_sid || call_sid : call_sid
        call = inbox_calls.find_by!(provider_call_id: lookup_sid)
        call.update!(parent_call_sid: parent_sid) if parent_sid.present? && call.parent_call_sid != parent_sid
        call
      end

      def inbox_calls
        Custom::Call.where(inbox_id: inbox.id, provider: :twilio)
      end

      # Two attempts, same action URL. Saying nothing on the first one is the
      # ordinary Gather default (no action_on_empty_result): Twilio just
      # reads on to the next verb, which is the second Gather. Saying
      # nothing on the second one does carry action_on_empty_result, so
      # #language still gets called — with Digits blank — and defaults to
      # Spanish there. No third verb needed after these two: every real path
      # (a digit on either attempt, or silence through both) ends by posting
      # to the same action exactly once.
      def language_menu_twiml
        ::Twilio::TwiML::VoiceResponse.new.tap do |response|
          response.gather(num_digits: 1, timeout: LANGUAGE_GATHER_TIMEOUT,
                           action: language_action_url, method: 'POST') do |gather|
            gather.say(message: LANGUAGE_PROMPT)
          end
          response.gather(num_digits: 1, timeout: LANGUAGE_GATHER_TIMEOUT,
                           action: language_action_url, method: 'POST', action_on_empty_result: true) do |gather|
            gather.say(message: LANGUAGE_PROMPT)
          end
        end.to_s
      end

      def find_call_for_language!
        inbox_calls.find_by!(provider_call_id: twilio_call_sid)
      end

      def language_action_url
        phone_digits = inbox_channel.phone_number.delete_prefix('+')
        Rails.application.routes.url_helpers.custom_twilio_voice_language_url(phone: phone_digits)
      end

      def conference_twiml(call)
        conference_sid = ensure_conference_sid!(call)

        ::Twilio::TwiML::VoiceResponse.new.tap do |response|
          response.dial do |dial|
            dial.conference(
              conference_sid,
              start_conference_on_enter: agent_leg?(twilio_from),
              end_conference_on_exit: false,
              record: 'record-from-start',
              recording_status_callback: recording_status_callback_url,
              recording_status_callback_event: 'completed',
              recording_status_callback_method: 'POST',
              status_callback: conference_status_callback_url,
              status_callback_event: 'start end join leave',
              status_callback_method: 'POST',
              participant_label: participant_label_for(twilio_from)
            )
          end
        end.to_s
      end

      def ensure_conference_sid!(call)
        return call.conference_sid if call.conference_sid.present?

        call.update!(conference_sid: call.default_conference_sid)
        call.conference_sid
      end

      def participant_label_for(from_number)
        return from_number.delete_prefix('client:') if from_number.start_with?('client:')

        'contact'
      end

      def conference_status_callback_url
        phone_digits = inbox_channel.phone_number.delete_prefix('+')
        Rails.application.routes.url_helpers.custom_twilio_voice_conference_status_url(phone: phone_digits)
      end

      def recording_status_callback_url
        phone_digits = inbox_channel.phone_number.delete_prefix('+')
        Rails.application.routes.url_helpers.custom_twilio_voice_recording_status_url(phone: phone_digits)
      end

      def find_call_for_conference!(friendly_name, call_sid)
        name = friendly_name.to_s
        call = inbox_calls.by_conference_sid(name).first if name.present?
        call || inbox_calls.find_by!(provider_call_id: call_sid)
      end

      def persist_twilio_conference_sid!(call, sid)
        return if sid.blank?
        return if call.twilio_conference_sid == sid

        call.update!(twilio_conference_sid: sid)
      end

      def verify_twilio_signature!
        signature = request.headers['X-Twilio-Signature'].to_s
        validator = ::Twilio::Security::RequestValidator.new(inbox_channel.auth_token)
        head :forbidden unless validator.validate(request.original_url, request.POST, signature)
      end

      def set_inbox!
        digits = params[:phone].to_s.gsub(/\D/, '')
        phone_number = "+#{digits}"
        channel = ::Channel::TwilioSms.find_by!(phone_number: phone_number)
        raise ActiveRecord::RecordNotFound, "Voice not enabled for #{phone_number}" unless channel.voice_enabled?

        @inbox = channel.inbox
      end

      def current_account
        @current_account ||= inbox_account
      end

      def participant_label
        params[:ParticipantLabel].to_s
      end

      attr_reader :inbox
      delegate :account, :channel, to: :inbox, prefix: true
    end
  end
end
