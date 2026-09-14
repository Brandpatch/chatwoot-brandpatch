/* global axios */
import ApiClient from './ApiClient';

class MyCallStatsAPI extends ApiClient {
  constructor() {
    // Singular resource: the endpoint answers for whoever is asking, so there
    // is no id to pass and no way to address another agent's figures.
    super('my_call_stats', { accountScoped: true, custom: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new MyCallStatsAPI();
