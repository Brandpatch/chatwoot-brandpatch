# frozen_string_literal: true

module Custom
  class Call < ApplicationRecord
    self.table_name = 'calls'

    STATUSES = %w[ringing in_progress completed no_answer failed rejected].freeze
    TERMINAL_STATUSES = %w[completed no_answer failed rejected].freeze

    # Who hung up on a call that was connected. Only these two endings are a
    # person: a ring that timed out or a carrier failure is already spelled out
    # by the status, and has nobody to name. Declining is not an ending either
    # — the router hands the call to the next agent and the caller waits on, so
    # a decline always ends later by one of these. It stays per turn, in
    # call_ring_attempts.outcome, the only place a call with several turns can
    # record a different answer for each agent.
    AGENT_HANGUP = 'agent_hangup'
    CALLER_HANGUP = 'caller_hangup'

    # Why an outbound call never connected, as far as the agent needs to care.
    #
    # Only the endings that change what they do next earn a name: fix the
    # number, try later, or ask somebody to look at the account. Twilio has
    # dozens of codes and translating all of them would be a table nobody reads
    # and everybody has to maintain, so the rest fall to UNREACHABLE, which at
    # least does not claim something untrue.
    INVALID_NUMBER = 'invalid_number'
    UNREACHABLE_NUMBER = 'unreachable_number'
    LINE_BUSY = 'line_busy'
    CALL_BLOCKED = 'call_blocked'
    DESTINATION_NOT_ALLOWED = 'destination_not_allowed'
    CARRIER_REJECTED = 'carrier_rejected'
    UNREACHABLE = 'unreachable'

    # Twilio's own codes, grouped by what the agent should do about them.
    # Documented at twilio.com/docs/api/errors; the mapping is deliberately
    # partial, and anything missing lands on UNREACHABLE with the raw code kept
    # in meta so an unmapped ending can be diagnosed without digging through
    # logs.
    FAILURE_REASON_BY_CODE = {
      # The number does not exist or is not assigned to anyone.
      '21217' => UNREACHABLE_NUMBER,
      '21214' => UNREACHABLE_NUMBER,
      '13224' => UNREACHABLE_NUMBER,
      # Malformed, or not a number Twilio can dial at all.
      '21211' => INVALID_NUMBER,
      '13223' => INVALID_NUMBER,
      # The carrier or Twilio refused to place it.
      '13225' => CARRIER_REJECTED,
      '32009' => CARRIER_REJECTED,
      # Blocked on purpose, by Twilio or by the recipient.
      '13226' => CALL_BLOCKED,
      '21610' => CALL_BLOCKED,
      # The account cannot call that destination: geo permissions or no funds.
      '21215' => DESTINATION_NOT_ALLOWED,
      '20003' => DESTINATION_NOT_ALLOWED
      # LINE_BUSY has no code here on purpose: Twilio reports a busy line as a
      # call status, not as an error, so it never arrives with one. The name
      # exists for the day that changes, or for a provider that does send it.
    }.freeze
    DISPLAY_DIRECTION = { 'incoming' => 'inbound', 'outgoing' => 'outbound' }.freeze
    DEFAULT_STUN_URL = 'stun:stun.l.google.com:19302'.freeze

    store_accessor :meta, :conference_sid, :twilio_conference_sid, :recording_sid,
                   :parent_call_sid, :initiated_at, :ended_at, :accepted_broadcast_at,
                   :conversation_created, :failure_reason, :provider_error_code

    enum :provider, { twilio: 0, whatsapp: 1 }
    enum :direction, { incoming: 0, outgoing: 1 }

    belongs_to :account
    belongs_to :inbox
    # Explicit ::Conversation because this class lives under Custom::, where a
    # bare Conversation now resolves to the Custom::Conversation prepend module
    # and Rails refuses it as an association target. Same trap as the other
    # prepend modules under this namespace.
    belongs_to :conversation, class_name: '::Conversation'
    belongs_to :contact
    belongs_to :message, class_name: '::Message', optional: true, inverse_of: :custom_call
    belongs_to :accepted_by_agent, class_name: 'User', optional: true
    belongs_to :current_ring_agent, class_name: 'User', optional: true

    has_one_attached :recording

    validates :provider_call_id, presence: true
    validates :provider, presence: true
    validates :direction, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    # Whether an agent was actually on the call. Neither column says so alone: a
    # caller who hangs up while it rings lands on 'completed' with no agent, and
    # finalize_call! stamps accepted_by_agent_id when an agent declines, so that
    # column by itself credits a rejection as an answer. The reports and the
    # call list share this definition so their figures agree.
    ANSWERED_SQL = "calls.accepted_by_agent_id IS NOT NULL AND calls.status <> 'rejected'"

    scope :answered,                 -> { where(ANSWERED_SQL) }
    scope :unanswered,               -> { where.not(ANSWERED_SQL) }
    scope :active,                   -> { where.not(status: TERMINAL_STATUSES) }
    scope :by_conference_sid,        ->(sid) { where("meta->>'conference_sid' = ?", sid) }
    scope :by_twilio_conference_sid, ->(sid) { where("meta->>'twilio_conference_sid' = ?", sid) }

    def self.find_by_provider_call_id(provider, sid)
      find_by(provider: provider, provider_call_id: sid)
    end

    def self.default_ice_servers
      urls = ENV.fetch('VOICE_CALL_STUN_URLS', DEFAULT_STUN_URL).split(',').filter_map { |u| u.strip.presence }
      [{ urls: urls }]
    end

    def self.direction_from_label(value)
      DISPLAY_DIRECTION.key(value) || value
    end

    def self.status_from_display(value)
      value.to_s.tr('-', '_')
    end

    def default_conference_sid
      "conf_account_#{account_id}_call_#{id}"
    end

    # The conversation of a call belongs to whoever answers it, unless somebody
    # was already working it.
    #
    # For a conversation this call created, the owner follows the call: each ring
    # turn hands it to the agent whose phone is ringing, and answering leaves it
    # with whoever picked up. So it always belongs to somebody who was actually
    # offered the call — and a call nobody answers ends up with the last agent
    # who let it ring, which is at least a real relationship to explain.
    #
    # That is also why Chatwoot's own auto-assignment is skipped for these
    # conversations (see Custom::Conversation): it stamps an owner on creation by
    # a round robin that knows nothing about calls, and would pick the very
    # agents the router just refused to ring.
    #
    # A conversation that already existed has a real owner who was working it,
    # and that one is respected — the ring turn never takes it away.
    def assign_conversation_to!(user_id)
      return if conversation.assigned_entity.present? && !conversation_created

      # Silently: the call is what the agent has to be told about, and the
      # assignment alert would announce it as a chat. See Custom::Conversation.
      conversation.brandpatch_silent_assignment = true
      ::Conversations::AssignmentService.new(conversation: conversation, assignee_id: user_id).perform
    end

    def ringing?      = status == 'ringing'
    def in_progress?  = status == 'in_progress'
    def terminal?     = TERMINAL_STATUSES.include?(status)
    def display_status = status.to_s.tr('_', '-')
    def direction_label = DISPLAY_DIRECTION[direction]

    def broadcast_voice_call_event(event, **extra)
      payload = {
        event: "voice_call.#{event}",
        data: { id: id, call_id: provider_call_id, provider: provider,
                # The display_id, as every other conversation payload sends:
                # the dashboard addresses conversations by it and so does the
                # conference endpoint. Sending the primary key instead only
                # looked right while a single account existed, where the two
                # sequences happened to march together.
                conversation_id: conversation.display_id, account_id: account_id,
                inbox_id: inbox_id,
                current_ring_agent_id: current_ring_agent_id }.merge(extra)
      }
      ActionCable.server.broadcast("account_#{account_id}", payload)
    end

    def from_number = incoming? ? contact.phone_number : inbox.channel&.phone_number
    def to_number   = incoming? ? inbox.channel&.phone_number : contact.phone_number

    def recording_url
      return nil unless recording.attached?

      Rails.application.routes.url_helpers.rails_blob_url(recording)
    end

    # An unmapped code still gets an answer rather than nothing: UNREACHABLE is
    # vague but true, and the raw code stays in meta for whoever has to find out
    # what it was.
    def self.failure_reason_for(error_code)
      return if error_code.blank?

      FAILURE_REASON_BY_CODE.fetch(error_code.to_s, UNREACHABLE)
    end

    def push_event_data
      {
        id: id,
        provider_call_id: provider_call_id,
        provider: provider,
        direction: direction,
        status: display_status,
        duration_seconds: duration_seconds,
        end_reason: end_reason,
        failure_reason: failure_reason,
        conference_sid: conference_sid,
        accepted_by_agent_id: accepted_by_agent_id,
        accepted_by_agent_name: accepted_by_agent&.available_name,
        current_ring_agent_id: current_ring_agent_id,
        started_at: started_at&.to_i,
        ended_at: ended_at,
        from_number: from_number,
        to_number: to_number,
        recording_url: recording_url,
        transcript: transcript
      }
    end
  end
end
