# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom Twilio voice webhook, agent leg', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:intruder) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:call) do
    Custom::Call.create!(account: account, inbox: channel.inbox, conversation: conversation, contact: conversation.contact,
                         provider: :twilio, direction: :incoming, status: 'ringing', provider_call_id: 'CAinbound',
                         current_ring_agent: agent)
  end
  let(:url) { "/twilio/voice/custom/call/#{channel.phone_number.delete_prefix('+')}" }

  before do
    allow_any_instance_of(Twilio::Security::RequestValidator).to receive(:validate).and_return(true) # rubocop:disable RSpec/AnyInstance
  end

  def agent_leg(user)
    post url, params: { From: "client:agent-#{user.id}-account-#{account.id}", Direction: 'inbound',
                        CallSid: 'CAleg', call_sid: call.provider_call_id }
  end

  it 'lets the agent the call is ringing for into the conference' do
    agent_leg(agent)

    expect(response.body).to include('<Conference')
  end

  it 'lets the agent who claimed the call in, as when it was taken from the queue' do
    call.update!(current_ring_agent: nil, accepted_by_agent: intruder)

    agent_leg(intruder)

    expect(response.body).to include('<Conference')
  end

  it 'hangs up on an agent the call does not belong to' do
    agent_leg(intruder)

    expect(response.body).to include('<Hangup')
    expect(response.body).not_to include('<Conference')
  end
end
