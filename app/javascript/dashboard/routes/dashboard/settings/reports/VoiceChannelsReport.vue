<script setup>
import { useI18n } from 'vue-i18n';
import ReportHeader from './components/ReportHeader.vue';

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col gap-4">
    <ReportHeader :header-title="t('VOICE_REPORTS.HEADER')" />
  </div>
</template>
