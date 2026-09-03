<script setup>
import { computed, h } from 'vue';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getPaginationRowModel,
} from '@tanstack/vue-table';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';

import Table from 'dashboard/components/table/Table.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import BaseCell from 'dashboard/components/table/BaseCell.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import AgentCell from './overview/AgentCell.vue';

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
const { uiSettings, updateUISettings } = useUISettings();

const PAGE_SIZE_KEY = 'voice_report_table_page_size';

const getPageSize = () => uiSettings.value[PAGE_SIZE_KEY] || 10;
const handlePageSizeChange = pageSize =>
  updateUISettings({ [PAGE_SIZE_KEY]: pageSize });

// Blank rather than a zero where the metric had nothing behind it: an agent
// who never picked up has no time to answer, and a zero there would read as
// answering instantly. BaseCell turns a blank into the same dash the other
// report tables use.
const formatSeconds = value => {
  if (value === null || value === undefined) return '';
  if (value < 60) return `${value}s`;

  return `${Math.floor(value / 60)}m ${Math.round(value % 60)}s`;
};

const FORMATTERS = {
  // A real agent always gets a number here, zero included, since a zero is
  // itself the finding. Only the unassigned row sends nothing, and that must
  // read as blank rather than as a zero it did not earn.
  count: value =>
    value === null || value === undefined ? '' : String(value),
  percent: value =>
    value === null || value === undefined ? '' : `${Math.round(value * 100)}%`,
  seconds: formatSeconds,
  minutes: value =>
    value === null || value === undefined ? '' : value.toFixed(2),
};

const cellFor = format => cellProps =>
  h(BaseCell, { content: FORMATTERS[format](cellProps.getValue()) });

// Missed calls and response rate exist only per agent: they count turns an
// agent was offered, which an inbox does not have. The inbox carries
// unattended calls instead — the ones nobody in the team took.
const METRIC_COLUMNS = {
  agent: [
    ['callsAnswered', 'ANSWERED', 'count'],
    ['missedCalls', 'MISSED', 'count'],
    ['responseRate', 'RESPONSE_RATE', 'percent'],
    ['avgTimeToAnswer', 'TIME_TO_ANSWER', 'seconds'],
    ['outboundCalls', 'OUTBOUND', 'count'],
    ['callMinutes', 'MINUTES', 'minutes'],
    ['outboundCallMinutes', 'OUTBOUND_MINUTES', 'minutes'],
    ['avgOutboundDuration', 'AVG_OUTBOUND', 'seconds'],
    ['avgTimeToCapture', 'TIME_TO_CAPTURE', 'seconds'],
    ['notes', 'NOTES', 'count'],
    ['resolvedConversations', 'RESOLVED', 'count'],
  ],
  inbox: [
    ['callsAnswered', 'ANSWERED', 'count'],
    ['unattendedCalls', 'UNATTENDED', 'count'],
    ['avgTimeToAnswer', 'TIME_TO_ANSWER', 'seconds'],
    ['outboundCalls', 'OUTBOUND', 'count'],
    ['callMinutes', 'MINUTES', 'minutes'],
    ['outboundCallMinutes', 'OUTBOUND_MINUTES', 'minutes'],
    ['avgOutboundDuration', 'AVG_OUTBOUND', 'seconds'],
    ['avgTimeToCapture', 'TIME_TO_CAPTURE', 'seconds'],
    ['notes', 'NOTES', 'count'],
    ['resolvedConversations', 'RESOLVED', 'count'],
  ],
};

const columnHelper = createColumnHelper();

// AgentCell reads agent/email/thumbnail off the row, so the rows are shaped to
// match it and the avatar treatment is shared with the overview report rather
// than reimplemented.
const columns = computed(() => {
  const isAgent = props.grouping === 'agent';

  const nameColumn = isAgent
    ? columnHelper.accessor('agent', {
        header: t('VOICE_REPORTS.COLUMNS.AGENT'),
        // The unassigned row is not a person, so it gets the plain label
        // instead of an avatar and an email it does not have.
        cell: cellProps =>
          cellProps.row.original.id === null
            ? h(BaseCell, { content: t('VOICE_REPORTS.UNASSIGNED') })
            : h(AgentCell, cellProps),
        size: 260,
      })
    : columnHelper.accessor('agent', {
        header: t('VOICE_REPORTS.COLUMNS.INBOX'),
        cell: cellProps => h(BaseCell, { content: cellProps.getValue() }),
        size: 260,
      });

  const metrics = METRIC_COLUMNS[props.grouping].map(([key, label, format]) =>
    columnHelper.accessor(key, {
      header: t(`VOICE_REPORTS.COLUMNS.${label}`),
      cell: cellFor(format),
      size: 120,
    })
  );

  return [nameColumn, ...metrics];
});

const tableData = computed(() =>
  props.rows.map(row => ({ ...row, agent: row.name }))
);

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
  getPaginationRowModel: getPaginationRowModel(),
  initialState: {
    pagination: { pageSize: getPageSize() },
  },
});
</script>

<template>
  <div class="flex flex-col flex-1">
    <Table :table="table" class="max-h-[calc(100vh-21.875rem)]" />
    <Pagination
      v-if="rows.length"
      class="mt-2"
      :table="table"
      show-page-size-selector
      :default-page-size="getPageSize()"
      @page-size-change="handlePageSizeChange"
    />
    <EmptyState v-if="!rows.length" :title="t('VOICE_REPORTS.EMPTY')" />
  </div>
</template>
