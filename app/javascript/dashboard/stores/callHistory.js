import camelcaseKeys from 'camelcase-keys';
import CallsAPI from 'dashboard/api/calls';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { defineStore } from 'pinia';

export const useCallHistoryStore = defineStore('callHistory', {
  state: () => ({
    records: [],
    meta: { count: 0, currentPage: 1, totalPages: 0 },
    uiFlags: { isFetching: false, isDownloading: false },
    fetchRequestToken: 0,
  }),

  actions: {
    async fetchCalls(params = {}) {
      this.uiFlags.isFetching = true;
      this.fetchRequestToken += 1;
      const requestToken = this.fetchRequestToken;
      try {
        const { data } = await CallsAPI.get(params);
        // A newer fetch (filter/page change) superseded this one; drop the result.
        if (this.fetchRequestToken !== requestToken) return this.records;
        this.records = camelcaseKeys(data.payload, { deep: true });
        this.meta = camelcaseKeys(data.meta);
        return this.records;
      } catch (error) {
        // Don't surface errors from a fetch that a newer request already replaced.
        if (this.fetchRequestToken !== requestToken) return this.records;
        // Drop the previous results so stale rows aren't shown under the new view.
        this.records = [];
        this.meta = { count: 0, currentPage: 1, totalPages: 0 };
        return throwErrorMessage(error);
      } finally {
        if (this.fetchRequestToken === requestToken) {
          this.uiFlags.isFetching = false;
        }
      }
    },

    // The whole period, not the page on screen, and the server renders it: the
    // list only ever holds 25 rows, and contact names are user-supplied text
    // that would run as spreadsheet formulas if written out here.
    //
    // isDownloading is separate from isFetching so the list does not blank
    // out behind a download that can take a few seconds on a wide period.
    async downloadCalls({ fileName, ...params } = {}) {
      this.uiFlags.isDownloading = true;
      try {
        const { data } = await CallsAPI.download({
          ...params,
          // The range is worked out in this browser's time zone, so the end of
          // a day reaches the server as an instant that is already the next
          // day in UTC. Sent along so every time in the file reads back as the
          // screen showed it. Negated: getTimezoneOffset reports inverted.
          utc_offset: -new Date().getTimezoneOffset(),
        });
        downloadCsvFile(fileName, data);
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.isDownloading = false;
      }
      return true;
    },
  },
});
