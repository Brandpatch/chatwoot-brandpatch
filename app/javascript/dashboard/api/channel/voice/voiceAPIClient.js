/* global axios */
import ApiClient from '../../ApiClient';
import ContactsAPI from '../../contacts';

class VoiceAPI extends ApiClient {
  constructor() {
    // Routes conference token/join/leave to the Brandpatch controllers under
    // /custom. Without this the requests land on the Enterprise controller,
    // which writes the same calls row through its own services and so skips
    // our ring tracking and status handling entirely.
    super('voice', { accountScoped: true, custom: true });
  }

  // eslint-disable-next-line class-methods-use-this
  initiateCall(contactId, inboxId) {
    return ContactsAPI.initiateCall(contactId, inboxId).then(r => r.data);
  }

  leaveConference({ inboxId, conversationId, callSid }) {
    return axios
      .delete(`${this.baseUrl()}/inboxes/${inboxId}/conference`, {
        params: { conversation_id: conversationId, call_sid: callSid },
      })
      .then(r => r.data);
  }

  joinConference({ conversationId, inboxId, callSid }) {
    return axios
      .post(`${this.baseUrl()}/inboxes/${inboxId}/conference`, {
        conversation_id: conversationId,
        call_sid: callSid,
      })
      .then(r => r.data);
  }

  getToken(inboxId) {
    if (!inboxId) return Promise.reject(new Error('Inbox ID is required'));
    return axios
      .get(`${this.baseUrl()}/inboxes/${inboxId}/conference/token`)
      .then(r => r.data);
  }
}

export default new VoiceAPI();
