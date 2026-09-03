<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { subDays, fromUnixTime } from 'date-fns';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import {
  generateReportURLParams,
  parseReportURLParams,
} from './helpers/reportFilterHelper';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ReportHeader from './components/ReportHeader.vue';
import VoiceStatsTable from './components/VoiceStatsTable.vue';
import VoiceMetricCards from './components/VoiceMetricCards.vue';
import { useCallStatsStore } from 'dashboard/stores/callStats';

const GROUPINGS = ['agent', 'inbox'];
const SECTIONS = ['attention', 'outbound', 'conversations'];
const DEFAULT_DAYS_BACK = 6;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const callStatsStore = useCallStatsStore();

const urlParams = parseReportURLParams(route.query);

const dateRange = ref(
  urlParams.from && urlParams.to
    ? [fromUnixTime(urlParams.from), fromUnixTime(urlParams.to)]
    : [subDays(new Date(), DEFAULT_DAYS_BACK), new Date()]
);
const rangeType = ref(urlParams.range || 'last7days');
const activeIndex = ref(Math.max(GROUPINGS.indexOf(route.query.group_by), 0));

const from = computed(() => getUnixStartOfDay(dateRange.value[0]));
const to = computed(() => getUnixEndOfDay(dateRange.value[1]));
const grouping = computed(() => GROUPINGS[activeIndex.value]);

const rows = computed(() => callStatsStore.rows);
const totals = computed(() => callStatsStore.totals);
const isFetching = computed(() => callStatsStore.uiFlags.isFetching);

const tabs = computed(() =>
  GROUPINGS.map(key => ({
    key,
    label: t(`VOICE_REPORTS.TABS.${key.toUpperCase()}`),
  }))
);

// Keeps the view shareable and survivable across a reload: a supervisor
// sending "the numbers for last week by agent" should not have to describe
// which filters to set.
const syncUrl = () => {
  router.replace({
    query: {
      ...generateReportURLParams({
        from: from.value,
        to: to.value,
        range: rangeType.value,
      }),
      group_by: grouping.value,
    },
  });
};

const fetchStats = () => {
  callStatsStore.fetchStats({
    groupBy: grouping.value,
    since: from.value,
    until: to.value,
  });
};

const onDateRangeChange = ([startDate, endDate, selectedRangeType]) => {
  dateRange.value = [startDate, endDate];
  rangeType.value = selectedRangeType;
  syncUrl();
  fetchStats();
};

const onTabChange = tab => {
  const index = GROUPINGS.indexOf(tab.key);
  if (index === -1 || index === activeIndex.value) return;

  activeIndex.value = index;
  syncUrl();
  fetchStats();
};

onMounted(fetchStats);
// The store is shared, so leaving without clearing would flash the previous
// grouping's figures on the way back in.
onUnmounted(() => callStatsStore.resetStats());
</script>

<template>
  <div class="flex flex-col gap-4">
    <ReportHeader :header-title="t('VOICE_REPORTS.HEADER')" />

    <div class="flex flex-col flex-wrap w-full gap-3 md:flex-row">
      <WootDatePicker
        v-model:date-range="dateRange"
        v-model:range-type="rangeType"
        @date-range-changed="onDateRangeChange"
      />
    </div>

    <TabBar
      :tabs="tabs"
      :initial-active-tab="activeIndex"
      @tab-changed="onTabChange"
    />

    <div v-if="isFetching" class="py-8 text-sm text-center text-n-slate-11">
      {{ t('VOICE_REPORTS.LOADING') }}
    </div>
    <template v-else>
      <VoiceMetricCards :totals="totals" />

      <section v-for="key in SECTIONS" :key="key" class="flex flex-col gap-2">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t(`VOICE_REPORTS.SECTIONS.${key.toUpperCase()}`) }}
        </h3>
        <VoiceStatsTable :grouping="grouping" :rows="rows" :section="key" />
      </section>
    </template>
  </div>
</template>
