# frozen_string_literal: true

require 'rails_helper'

# Twilio's REST resources are built dynamically, so there is no class to verify these doubles against.
# rubocop:disable RSpec/VerifiedDoubles

RSpec.describe Custom::Voice::DialerCustomerLeg do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact) }
  let(:calls_api) { double }
  let(:leg) { double(update: true) }
  let(:twilio_client) { double(conferences: double(list: [])) }
  let(:call) do
    Custom::Call.create!(account: account, inbox: channel.inbox, conversation: conversation, contact: conversation.contact,
                         provider: :twilio, direction: :outgoing, status: 'ringing', accepted_by_agent: agent,
                         provider_call_id: 'dialer-abc',
                         meta: { 'dialer' => { 'external_id' => 'lead-1', 'phase' => 'awaiting_agent' } })
  end
  let(:agent_label) { "agent-#{agent.id}-account-#{account.id}" }

  before do
    allow(twilio_client).to receive(:calls) { |sid = nil| sid ? leg : calls_api }
    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
  end

  def agent_joins
    Custom::Voice::Conference::Manager.new(call: Custom::Call.find(call.id), event: 'join', participant_label: agent_label).process
  end

  describe 'dialling on the agent join' do
    it 'dials the customer once with async AMD and keeps the placeholder as the call id' do
      allow(calls_api).to receive(:create).and_return(double(sid: 'CAcustomer'))

      agent_joins
      agent_joins

      expect(calls_api).to have_received(:create).once.with(
        hash_including(to: conversation.contact.phone_number, machine_detection: 'Enable', async_amd: 'true',
                       async_amd_status_callback: a_string_including('amd_status', 'dialer_sid=dialer-abc'),
                       status_callback: a_string_including('dialer_sid=dialer-abc'))
      )
      expect(call.reload.provider_call_id).to eq('dialer-abc')
      expect(call.dialer).to include('phase' => 'dialing', 'customer_call_sid' => 'CAcustomer')
      expect(call.provider_leg_sid).to eq('CAcustomer')
      expect(call.status).to eq('ringing')
    end

    it 'does not dial for an agent other than the reserved one' do
      allow(calls_api).to receive(:create)
      other = create(:user, account: account, role: :agent)

      Custom::Voice::Conference::Manager.new(call: call, event: 'join', participant_label: "agent-#{other.id}-account-#{account.id}").process

      expect(calls_api).not_to have_received(:create)
    end

    it 'fails the call when Twilio refuses the number' do
      error = Twilio::REST::RestError.new('bad number', double(status_code: 400, body: { 'code' => 21_211, 'message' => 'bad' }))
      allow(calls_api).to receive(:create).and_raise(error)

      agent_joins

      expect(call.reload.status).to eq('failed')
      expect(call.failure_reason).to eq(Custom::Call::INVALID_NUMBER)
    end
  end

  describe '#record_answered_by!' do
    before { call.merge_dialer!('phase' => 'dialing', 'customer_call_sid' => 'CAcustomer') }

    it 'hangs up on a machine and records why' do
      described_class.new(call: call).record_answered_by!('machine_start')

      expect(twilio_client).to have_received(:calls).with('CAcustomer')
      expect(leg).to have_received(:update).with(status: 'completed')
      expect(call.reload.dialer).to include('answered_by' => 'machine_start', 'end_reason' => 'machine')
    end

    it 'leaves a human alone' do
      described_class.new(call: call).record_answered_by!('human')

      expect(leg).not_to have_received(:update)
      expect(call.reload.dialer).to include('answered_by' => 'human')
      expect(call.dialer).not_to have_key('end_reason')
    end
  end

  describe Custom::Voice::DialerAgentJoinTimeoutJob do
    it 'frees an agent who never joined' do
      described_class.perform_now(call.id)

      expect(call.reload.status).to eq('failed')
      expect(call.dialer['end_reason']).to eq('agent_did_not_join')
      expect(Custom::Call.active.where(accepted_by_agent_id: agent.id)).to be_empty
    end

    it 'leaves a call alone once its customer is being dialled' do
      call.merge_dialer!('phase' => 'dialing')

      described_class.perform_now(call.id)

      expect(call.reload.status).to eq('ringing')
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
