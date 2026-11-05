/* global axios */
import ApiClient from './ApiClient';

class CallsAPI extends ApiClient {
  constructor() {
    super('calls', { accountScoped: true, custom: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  download(params = {}) {
    return axios.get(`${this.url}/csv`, { params });
  }
}

export default new CallsAPI();
