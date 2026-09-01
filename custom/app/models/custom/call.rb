# frozen_string_literal: true

module Custom
  class Call < ApplicationRecord
    self.table_name = 'calls'

    STATUSES = %w[ringing in_progress completed no_answer failed rejected].freeze
    TERMINAL_STATUSES = %w[completed no_answer failed rejected].freeze
    DISPLAY_DIRECTION = { 'incoming' => 'inbound', 'outgoing' => 'outbound' }.freeze
    DEFAULT_STUN_URL = 'stun:stun.l.google.com:19302'.freeze

    store_accessor :meta, :conference_sid, :twilio_conference_sid, :recording_sid,
                   :parent_call_sid, :initiated_at, :ended_at, :accepted_broadcast_at

    enum :provider, { twilio: 0, whatsapp: 1 }
    enum :direction, { incoming: 0, outgoing: 1 }

    belongs_to :account
    belongs_to :inbox
    belongs_to :conversation
    belongs_to :contact
    belongs_to :message, class_name: '::Message', optional: true, inverse_of: :custom_call
    belongs_to :accepted_by_agent, class_name: 'User', optional: true
    belongs_to :current_ring_agent, class_name: 'User', optional: true

    has_one_attached :recording

    validates :provider_call_id, presence: true
    validates :provider, presence: true
    validates :direction, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

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

    def ringing?      = status == 'ringing'
    def in_progress?  = status == 'in_progress'
    def terminal?     = TERMINAL_STATUSES.include?(status)
    def display_status = status.to_s.tr('_', '-')
    def direction_label = DISPLAY_DIRECTION[direction]

    def broadcast_voice_call_event(event, **extra)
      payload = {
        event: "voice_call.#{event}",
        data: { id: id, call_id: provider_call_id, provider: provider,
                conversation_id: conversation_id, account_id: account_id,
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

    def push_event_data
      {
        id: id,
        provider_call_id: provider_call_id,
        provider: provider,
        direction: direction,
        status: display_status,
        duration_seconds: duration_seconds,
        end_reason: end_reason,
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
