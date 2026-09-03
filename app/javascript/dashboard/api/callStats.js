/* global axios */
import ApiClient from './ApiClient';

class CallStatsAPI extends ApiClient {
  constructor() {
    // Only /custom exposes this endpoint, so the prefix is required rather than
    // optional here — without it the request 404s instead of quietly landing on
    // a core controller, which is how the conference client went unnoticed.
    super('call_stats', { accountScoped: true, custom: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new CallStatsAPI();
