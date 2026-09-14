import camelcaseKeys from 'camelcase-keys';
import MyCallStatsAPI from 'dashboard/api/myCallStats';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { defineStore } from 'pinia';

export const useMyCallStatsStore = defineStore('myCallStats', {
  state: () => ({
    summary: {},
    uiFlags: { isFetching: false },
    fetchRequestToken: 0,
  }),

  actions: {
    // Moving the date range fires a new fetch while the previous one may still
    // be in flight, and the two can land out of order. The token makes the
    // newest request the only one allowed to write.
    async fetchSummary({ since, until, inboxId } = {}) {
      this.uiFlags.isFetching = true;
      this.fetchRequestToken += 1;
      const requestToken = this.fetchRequestToken;

      try {
        const { data } = await MyCallStatsAPI.get({
          since,
          until,
          ...(inboxId ? { inbox_id: inboxId } : {}),
        });
        if (this.fetchRequestToken !== requestToken) return this.summary;
        this.summary = camelcaseKeys(data, { deep: true });
        return this.summary;
      } catch (error) {
        if (this.fetchRequestToken !== requestToken) return this.summary;
        // Drop the previous figures rather than leave numbers from another
        // period sitting above the list they no longer describe.
        this.summary = {};
        return throwErrorMessage(error);
      } finally {
        if (this.fetchRequestToken === requestToken) {
          this.uiFlags.isFetching = false;
        }
      }
    },
  },
});
