<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';

const props = defineProps({
  grouping: {
    type: String,
    required: true,
    validator: value => ['agent', 'inbox'].includes(value),
  },
  rows: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

// Missed calls and response rate exist only per agent: they count turns an
// agent was offered, which an inbox does not have. The inbox carries
// unattended calls instead — the ones nobody in the team took.
const COLUMNS = {
  agent: [
    { key: 'name', label: 'AGENT', format: 'text' },
    { key: 'callsAnswered', label: 'ANSWERED', format: 'count' },
    { key: 'missedCalls', label: 'MISSED', format: 'count' },
    { key: 'responseRate', label: 'RESPONSE_RATE', format: 'percent' },
    { key: 'avgTimeToAnswer', label: 'TIME_TO_ANSWER', format: 'seconds' },
    { key: 'outboundCalls', label: 'OUTBOUND', format: 'count' },
    { key: 'callMinutes', label: 'MINUTES', format: 'minutes' },
    {
      key: 'outboundCallMinutes',
      label: 'OUTBOUND_MINUTES',
      format: 'minutes',
    },
    { key: 'avgOutboundDuration', label: 'AVG_OUTBOUND', format: 'seconds' },
    { key: 'avgTimeToCapture', label: 'TIME_TO_CAPTURE', format: 'seconds' },
    { key: 'notes', label: 'NOTES', format: 'count' },
    { key: 'resolvedConversations', label: 'RESOLVED', format: 'count' },
  ],
  inbox: [
    { key: 'name', label: 'INBOX', format: 'text' },
    { key: 'callsAnswered', label: 'ANSWERED', format: 'count' },
    { key: 'unattendedCalls', label: 'UNATTENDED', format: 'count' },
    { key: 'avgTimeToAnswer', label: 'TIME_TO_ANSWER', format: 'seconds' },
    { key: 'outboundCalls', label: 'OUTBOUND', format: 'count' },
    { key: 'callMinutes', label: 'MINUTES', format: 'minutes' },
    {
      key: 'outboundCallMinutes',
      label: 'OUTBOUND_MINUTES',
      format: 'minutes',
    },
    { key: 'avgOutboundDuration', label: 'AVG_OUTBOUND', format: 'seconds' },
    { key: 'avgTimeToCapture', label: 'TIME_TO_CAPTURE', format: 'seconds' },
    { key: 'notes', label: 'NOTES', format: 'count' },
    { key: 'resolvedConversations', label: 'RESOLVED', format: 'count' },
  ],
};

const columns = computed(() => COLUMNS[props.grouping] ?? COLUMNS.agent);
const headers = computed(() =>
  columns.value.map(column => t(`VOICE_REPORTS.COLUMNS.${column.label}`))
);

// A dash rather than a zero where the metric had nothing to average: an agent
// who never picked up has no time to answer, which is not the same as
// answering instantly.
const EMPTY = '—';

const formatSeconds = value => {
  if (value === null || value === undefined) return EMPTY;
  if (value < 60) return `${value}s`;

  const minutes = Math.floor(value / 60);
  const seconds = Math.round(value % 60);
  return `${minutes}m ${seconds}s`;
};

const formatCell = (row, column) => {
  const value = row[column.key];

  switch (column.format) {
    case 'percent':
      return value === null || value === undefined
        ? EMPTY
        : `${Math.round(value * 100)}%`;
    case 'seconds':
      return formatSeconds(value);
    case 'minutes':
      return value ? value.toFixed(2) : '0';
    case 'count':
      return value ?? 0;
    default:
      return value ?? EMPTY;
  }
};
</script>

<template>
  <div class="w-full overflow-x-auto">
    <BaseTable
      :headers="headers"
      :items="rows"
      :no-data-message="t('VOICE_REPORTS.EMPTY')"
    >
      <template #row="{ items }">
        <tr v-for="row in items" :key="row.id">
          <td
            v-for="column in columns"
            :key="column.key"
            class="py-3 whitespace-nowrap ltr:pr-4 rtl:pl-4 text-body-main tabular-nums"
            :class="
              column.format === 'text'
                ? 'text-n-slate-12 font-medium'
                : 'text-n-slate-11'
            "
          >
            {{ formatCell(row, column) }}
          </td>
        </tr>
      </template>
    </BaseTable>
  </div>
</template>
