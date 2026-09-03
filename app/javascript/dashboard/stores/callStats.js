import camelcaseKeys from 'camelcase-keys';
import CallStatsAPI from 'dashboard/api/callStats';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { defineStore } from 'pinia';

export const useCallStatsStore = defineStore('callStats', {
  state: () => ({
    rows: [],
    totals: {},
    uiFlags: { isFetching: false },
    fetchRequestToken: 0,
  }),

  actions: {
    // Switching tab or moving the date range fires a new fetch while the
    // previous one may still be in flight, and the two can land out of order.
    // The token makes the newest request the only one allowed to write.
    async fetchStats({ groupBy, since, until, inboxId } = {}) {
      this.uiFlags.isFetching = true;
      this.fetchRequestToken += 1;
      const requestToken = this.fetchRequestToken;

      try {
        const { data } = await CallStatsAPI.get({
          group_by: groupBy,
          since,
          until,
          ...(inboxId ? { inbox_id: inboxId } : {}),
        });
        if (this.fetchRequestToken !== requestToken) return this.rows;
        const payload = camelcaseKeys(data, { deep: true });
        this.rows = payload.rows ?? [];
        this.totals = payload.totals ?? {};
        return this.rows;
      } catch (error) {
        if (this.fetchRequestToken !== requestToken) return this.rows;
        // Drop the previous figures so numbers from the old grouping aren't
        // read under the new one's column headings.
        this.rows = [];
        this.totals = {};
        return throwErrorMessage(error);
      } finally {
        if (this.fetchRequestToken === requestToken) {
          this.uiFlags.isFetching = false;
        }
      }
    },

    resetStats() {
      this.rows = [];
      this.totals = {};
      this.uiFlags.isFetching = false;
    },
  },
});
