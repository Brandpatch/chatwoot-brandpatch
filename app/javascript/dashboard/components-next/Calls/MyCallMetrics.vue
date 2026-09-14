<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  summary: {
    type: Object,
    default: () => ({}),
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const EMPTY = '---';

// Blank rather than a zero where there was nothing to measure: an agent who
// answered nothing has no time to answer, and a zero there would read as
// answering instantly. A zero call count, on the other hand, is a real figure.
const formatSeconds = value => {
  if (value === null || value === undefined) return EMPTY;
  if (value < 60) return `${value}s`;

  return `${Math.floor(value / 60)}m ${Math.round(value % 60)}s`;
};

const asCount = value =>
  value === null || value === undefined ? EMPTY : String(value);

const cards = computed(() => {
  const summary = props.summary;

  return [
    { key: 'ANSWERED', value: asCount(summary.callsAnswered) },
    { key: 'OUTBOUND', value: asCount(summary.outboundCalls) },
    { key: 'MISSED', value: asCount(summary.missedCalls) },
    { key: 'MINUTES', value: asCount(summary.callMinutes) },
    { key: 'TIME_TO_ANSWER', value: formatSeconds(summary.avgTimeToAnswer) },
  ];
});
</script>

<template>
  <div
    class="flex flex-wrap gap-6 mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
  >
    <!-- Each card is a column whose label grows to fill, so the values line up
         along the bottom however many lines a label takes. -->
    <div
      v-for="card in cards"
      :key="card.key"
      class="flex flex-col flex-1 min-w-32"
    >
      <h3
        class="flex items-start flex-1 m-0 text-sm font-medium text-n-slate-11"
      >
        <span>{{ t(`CALLS_PAGE.MY_METRICS.${card.key}.LABEL`) }}</span>
        <fluent-icon
          v-tooltip="t(`CALLS_PAGE.MY_METRICS.${card.key}.TOOLTIP`)"
          size="14"
          icon="info"
          class="text-n-slate-11 my-0 mx-1 mt-0.5 shrink-0"
        />
      </h3>
      <h4 class="mt-1 mb-0 text-2xl text-n-slate-12">
        <span v-if="isLoading" class="text-n-slate-10">{{ EMPTY }}</span>
        <span v-else>{{ card.value }}</span>
      </h4>
    </div>
  </div>
</template>
