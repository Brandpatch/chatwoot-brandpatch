<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportMetricCard from './ReportMetricCard.vue';

const props = defineProps({
  totals: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const EMPTY = '---';

const formatSeconds = value => {
  if (value === null || value === undefined) return EMPTY;
  if (value < 60) return `${value}s`;

  return `${Math.floor(value / 60)}m ${Math.round(value % 60)}s`;
};

// Period figures for the whole scope. They read the same in both groupings
// because received and unattended calls belong to the inbox, not to an agent,
// and the rate across everyone is not the average of the per-agent rates.
const cards = computed(() => {
  const totals = props.totals;

  return [
    { key: 'RECEIVED', value: String(totals.receivedCalls ?? 0) },
    { key: 'ANSWERED', value: String(totals.callsAnswered ?? 0) },
    { key: 'UNATTENDED', value: String(totals.unattendedCalls ?? 0) },
    {
      key: 'RESPONSE_RATE',
      value:
        totals.responseRate === null || totals.responseRate === undefined
          ? EMPTY
          : `${Math.round(totals.responseRate * 100)}%`,
    },
    { key: 'TIME_TO_ANSWER', value: formatSeconds(totals.avgTimeToAnswer) },
    {
      key: 'MINUTES',
      value:
        totals.callMinutes === null || totals.callMinutes === undefined
          ? EMPTY
          : String(totals.callMinutes),
    },
  ];
});
</script>

<template>
  <div
    class="flex flex-wrap gap-4 mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
  >
    <ReportMetricCard
      v-for="card in cards"
      :key="card.key"
      class="flex-1 min-w-32"
      :label="t(`VOICE_REPORTS.SUMMARY.${card.key}.LABEL`)"
      :info-text="t(`VOICE_REPORTS.SUMMARY.${card.key}.TOOLTIP`)"
      :value="card.value"
    />
  </div>
</template>
