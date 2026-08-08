import ApiClient from './ApiClient';

class CustomRole extends ApiClient {
  constructor() {
    super('custom_roles', { accountScoped: true, custom: true });
  }
}

export default new CustomRole();
