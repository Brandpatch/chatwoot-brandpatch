/* global axios */
import ApiClient from './ApiClient';

class VoiceCallerIdsAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true, custom: true });
  }

  get(inboxId) {
    return axios.get(`${this.url}/${inboxId}/voice_caller_ids`);
  }
}

export default new VoiceCallerIdsAPI();
