# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        # The account-wide switch that stops inbound calls reaching agents
        # while leaving messaging untouched. See Custom::Concerns::Account for
        # why the pause is not expressed through availability or membership.
        #
        # Administrators only. It silences the phone for a whole business, and
        # the people who asked for it are the supervisors running the meeting.
        #
        # Singular on purpose: there is one switch per account, so there is no id
        # to address a second one with.
        class InboundCallPauseController < ::Api::V1::Accounts::BaseController
          before_action :check_admin_authorization?

          def show
            render json: payload
          end

          def update
            paused? ? Current.account.brandpatch_pause_inbound_calls! : Current.account.brandpatch_resume_inbound_calls!
            render json: payload
          end

          private

          # Required rather than defaulted: a request that forgot to say which
          # way to move the switch is a bug in the caller, and guessing 'resume'
          # would quietly turn the phones back on in the middle of a meeting.
          def paused?
            ActiveModel::Type::Boolean.new.cast(params.require(:paused))
          end

          def payload
            paused_at = Current.account.brandpatch_inbound_calls_paused_at

            {
              paused: paused_at.present?,
              paused_at: paused_at&.to_i
            }
          end
        end
      end
    end
  end
end
