# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom dialer calls API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account) }
  let(:inbox) { channel.inbox }
  let(:url) { "/custom/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/dialer_calls" }
  let(:body) { { phone_number: '+15550001111', name: 'Lead Name', external_id: 'lead-1', note: 'Wants a quote', metadata: { source: 'fb' } } }
  let(:online) { { agent.id.to_s => 'online' } }

  before do
    account.enable_features!('auto_dialer_brandpatch')
    create(:inbox_member, inbox: inbox, user: agent)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(online)
  end

  describe 'POST dialer_calls' do
    it 'reserves the free agent and builds the call without dialling the customer' do
      expect(Custom::Voice::Provider::Twilio::Adapter).not_to receive(:new)

      expect do
        post url, params: body, headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Custom::Voice::DialerAgentJoinTimeoutJob)

      expect(response).to have_http_status(:created)
      call = Custom::Call.find(response.parsed_body['call_id'])
      expect(response.parsed_body).to include('agent_id' => agent.id, 'external_id' => 'lead-1',
                                              'conversation_id' => call.conversation.display_id)
      expect(call).to have_attributes(direction: 'outgoing', status: 'ringing', accepted_by_agent_id: agent.id)
      expect(call.provider_call_id).to start_with('dialer-')
      expect(call.dialer).to include('external_id' => 'lead-1', 'phase' => 'awaiting_agent', 'metadata' => { 'source' => 'fb' })
    end

    it 'creates the lead as a contact and leaves the note on the conversation' do
      post url, params: body, headers: admin.create_new_auth_token, as: :json

      call = Custom::Call.find(response.parsed_body['call_id'])
      expect(call.contact).to have_attributes(name: 'Lead Name', phone_number: '+15550001111')
      expect(call.conversation.messages.where(private: true).last.content).to eq('Wants a quote')
    end

    it 'leaves the reserved agent occupied for the next request' do
      post url, params: body, headers: admin.create_new_auth_token, as: :json
      post url, params: body.merge(external_id: 'lead-2', phone_number: '+15550002222'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('no_agent_available')
    end

    it 'refuses a lead that already has a live dialer call' do
      other = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: inbox, user: other)
      online[other.id.to_s] = 'online'

      post url, params: body, headers: admin.create_new_auth_token, as: :json
      post url, params: body, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('already_in_progress')
    end

    it 'stands down while an inbound caller waits in the queue' do
      conversation = create(:conversation, account: account, inbox: inbox)
      Custom::Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                           provider: :twilio, direction: :incoming, status: 'ringing', provider_call_id: 'CAqueued')

      post url, params: body, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('inbound_waiting')
    end

    it 'stands down while the account is paused' do
      account.brandpatch_pause_inbound_calls!

      post url, params: body, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['error']).to eq('paused')
    end

    it 'skips agents who are offline' do
      online[agent.id.to_s] = 'offline'

      post url, params: body, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['error']).to eq('no_agent_available')
    end

    it 'rejects a number that is not E.164' do
      post url, params: body.merge(phone_number: '5550001111'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'is not there for agents' do
      post url, params: body, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'is not there without the flag' do
      account.disable_features!('auto_dialer_brandpatch')

      post url, params: body, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET dialer_calls' do
    it 'lists dialer calls only, with their outcome' do
      post url, params: body, headers: admin.create_new_auth_token, as: :json
      call = Custom::Call.find(response.parsed_body['call_id'])
      call.merge_dialer!('answered_by' => 'machine_start', 'end_reason' => 'machine')
      conversation = create(:conversation, account: account, inbox: inbox)
      Custom::Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                           provider: :twilio, direction: :outgoing, status: 'completed', provider_call_id: 'CAmanual')

      get "/custom/api/v1/accounts/#{account.id}/dialer_calls", params: { updated_since: 1.hour.ago.to_i },
                                                                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('call_id')).to eq([call.id])
      expect(response.parsed_body['payload'].first).to include(
        'external_id' => 'lead-1', 'answered_by' => 'machine_start', 'end_reason' => 'machine',
        'agent_id' => agent.id, 'display_kind' => 'ongoing', 'phase' => 'awaiting_agent'
      )
    end

    it 'filters by updated_since' do
      post url, params: body, headers: admin.create_new_auth_token, as: :json

      get "/custom/api/v1/accounts/#{account.id}/dialer_calls", params: { updated_since: 1.minute.from_now.iso8601 },
                                                                headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to be_empty
    end
  end
end
