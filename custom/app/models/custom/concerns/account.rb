# frozen_string_literal: true

module Custom
  module Concerns
    module Account
      extend ActiveSupport::Concern

      # [brandpatch] Account-wide pause for inbound calling.
      #
      # Customer service stops taking calls during their weekly meeting. They did
      # it by unassigning every agent from every inbox: 544 agent-inbox pairs
      # across 15 inboxes. That also took them off messaging, which is the one
      # thing they asked to keep, because voice rides on the SMS inboxes —
      # `Compinche` carried 122.927 messages alongside 37.505 calls over 30 days.
      #
      # Availability cannot express it either: one per-account status shared by
      # calls and conversation auto-assignment, so going offline silences both.
      # The pause belongs to the voice channel, and Custom::Voice::CallRouter is
      # its only reader.
      #
      # It lives in this concern and NOT in a Custom::Account prepend module,
      # which is where it was first written. Defining that constant made the
      # bare `belongs_to :account` in Custom::Call and Custom::CallRingAttempt
      # resolve to the module instead of ::Account, and every inbound call died
      # on "The Account model class ... is not an ActiveRecord::Base subclass".
      # Custom::CustomRole already carried an explicit class_name: '::Account'
      # against exactly this. A concern adds no constant, so it cannot repeat it.
      BRANDPATCH_INBOUND_CALLS_PAUSED_AT = 'brandpatch_inbound_calls_paused_at'

      included do
        has_many :brandpatch_custom_roles, class_name: 'Custom::CustomRole', foreign_key: :account_id,
                                          inverse_of: :account, dependent: :destroy_async
        has_many :custom_calls, class_name: 'Custom::Call', dependent: :destroy_async
      end

      def brandpatch_inbound_calls_paused?
        brandpatch_inbound_calls_paused_at.present?
      end

      def brandpatch_inbound_calls_paused_at
        epoch = settings.to_h[BRANDPATCH_INBOUND_CALLS_PAUSED_AT]
        epoch.present? ? Time.zone.at(epoch.to_i) : nil
      end

      # Re-pausing keeps the original instant: "paused since" is only worth
      # showing if a second click cannot quietly reset it back to nothing. One
      # switch is much easier to forget than 544 unassignments were.
      def brandpatch_pause_inbound_calls!
        return if brandpatch_inbound_calls_paused?

        update!(settings: settings.to_h.merge(BRANDPATCH_INBOUND_CALLS_PAUSED_AT => Time.zone.now.to_i))
      end

      def brandpatch_resume_inbound_calls!
        return unless brandpatch_inbound_calls_paused?

        update!(settings: settings.to_h.except(BRANDPATCH_INBOUND_CALLS_PAUSED_AT))
      end
    end
  end
end
