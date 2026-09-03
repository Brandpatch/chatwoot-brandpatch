<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

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

const asCount = value =>
  value === null || value === undefined ? EMPTY : String(value);

// Period figures for the whole scope. They read the same in both groupings
// because received and unattended calls belong to the inbox, not to an agent,
// and the rate across everyone is not the average of the per-agent rates.
const cards = computed(() => {
  const totals = props.totals;

  return [
    { key: 'RECEIVED', value: asCount(totals.receivedCalls) },
    { key: 'ANSWERED', value: asCount(totals.callsAnswered) },
    { key: 'UNATTENDED', value: asCount(totals.unattendedCalls) },
    {
      key: 'RESPONSE_RATE',
      value:
        totals.responseRate === null || totals.responseRate === undefined
          ? EMPTY
          : `${Math.round(totals.responseRate * 100)}%`,
    },
    { key: 'TIME_TO_ANSWER', value: formatSeconds(totals.avgTimeToAnswer) },
    { key: 'MINUTES', value: asCount(totals.callMinutes) },
  ];
});
</script>

<template>
  <div
    class="flex flex-wrap gap-6 mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
  >
    <!-- Each card is a column whose label grows to fill, so the values line up
         along the bottom however many lines a label takes. A fixed label height
         would only hold for one language and one viewport width. -->
    <div
      v-for="card in cards"
      :key="card.key"
      class="flex flex-col flex-1 min-w-32"
    >
      <h3
        class="flex items-start flex-1 m-0 text-sm font-medium text-n-slate-11"
      >
        <span>{{ t(`VOICE_REPORTS.SUMMARY.${card.key}.LABEL`) }}</span>
        <fluent-icon
          v-tooltip="t(`VOICE_REPORTS.SUMMARY.${card.key}.TOOLTIP`)"
          size="14"
          icon="info"
          class="text-n-slate-11 my-0 mx-1 mt-0.5 shrink-0"
        />
      </h3>
      <h4 class="mt-1 mb-0 text-2xl text-n-slate-12">{{ card.value }}</h4>
    </div>
  </div>
</template>
