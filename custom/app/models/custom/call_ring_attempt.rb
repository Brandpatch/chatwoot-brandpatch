# frozen_string_literal: true

# One row per turn an agent was given to answer a call. The router only hands a
# turn to an agent who is online and free, so every row here is a call the agent
# could have taken — which is what makes the per-agent metrics fair.
module Custom
  class CallRingAttempt < ApplicationRecord
    self.table_name = 'call_ring_attempts'

    ANSWERED = 'answered'
    TIMEOUT = 'timeout'
    REJECTED = 'rejected'
    CALLER_HANGUP = 'caller_hangup'

    OUTCOMES = [ANSWERED, TIMEOUT, REJECTED, CALLER_HANGUP].freeze
    # caller_hangup is deliberately excluded: the caller gave up during this
    # agent's turn, which is not something to hold against them.
    MISSED_OUTCOMES = [TIMEOUT, REJECTED].freeze

    belongs_to :account
    belongs_to :call, class_name: 'Custom::Call'
    belongs_to :agent, class_name: 'User'

    validates :rang_at, presence: true
    validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

    scope :unfinished, -> { where(ended_at: nil) }
    scope :answered,   -> { where(outcome: ANSWERED) }
    scope :missed,     -> { where(outcome: MISSED_OUTCOMES) }
    # The denominator for response rate: turns whose outcome was the agent's to decide.
    scope :attributable, -> { where(outcome: [ANSWERED] + MISSED_OUTCOMES) }
  end
end
