<script>
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import VoiceCallerIdsAPI from 'dashboard/api/voiceCallerIds';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import NextSelect from 'dashboard/components-next/select/Select.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

export default {
  components: {
    SettingsFieldSection,
    SettingsToggleSection,
    NextSelect,
    NextInput,
    NextButton,
    Spinner,
  },
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  data() {
    return {
      voiceEnabled: this.inbox.voice_enabled || false,
      inboundCallsEnabled: this.inbox.inbound_calls_enabled !== false,
      apiKeySid: this.inbox.api_key_sid || '',
      apiKeySecret: '',
      ringTimeoutSeconds: this.inbox.ring_timeout_seconds || 30,
      maxWaitSeconds: this.inbox.max_wait_seconds || 300,
      voiceLanguageMenuEnabled: this.inbox.voice_language_menu_enabled || false,
      voiceCallerId: this.inbox.voice_caller_id || '',
      callerIdChoices: [],
      isLoadingCallerIds: false,
      callerIdsLoadFailed: false,
      isUpdating: false,
      isTogglingInbound: false,
    };
  },
  computed: {
    isWhatsApp() {
      return this.inbox.medium === 'whatsapp';
    },
    voiceDescription() {
      return this.isWhatsApp
        ? this.$t(
            'INBOX_MGMT.VOICE_CONFIGURATION.ENABLE_VOICE.WHATSAPP_DESCRIPTION'
          )
        : this.$t('INBOX_MGMT.VOICE_CONFIGURATION.ENABLE_VOICE.DESCRIPTION');
    },
    inboundDescription() {
      return this.isWhatsApp
        ? this.$t('INBOX_MGMT.VOICE_CONFIGURATION.INBOUND.WHATSAPP_DESCRIPTION')
        : this.$t('INBOX_MGMT.VOICE_CONFIGURATION.INBOUND.DESCRIPTION');
    },
    isVoiceConfigured() {
      return !!this.inbox.voice_configured;
    },
    hasApiKeySid() {
      return !!this.inbox.api_key_sid;
    },
    hasExistingCredentials() {
      return this.hasApiKeySid && !!this.inbox.has_api_key_secret;
    },
    needsCredentials() {
      return (
        this.voiceEnabled &&
        !this.isVoiceConfigured &&
        !this.hasExistingCredentials
      );
    },
    needsApiKeySid() {
      return this.needsCredentials && !this.hasApiKeySid;
    },
    callerIdOptions() {
      const ownNumber = this.inbox.phone_number;
      const options = [
        {
          value: '',
          label: this.$t(
            'INBOX_MGMT.VOICE_CONFIGURATION.CALLER_ID.INBOX_NUMBER',
            { number: ownNumber }
          ),
        },
      ];
      this.callerIdChoices
        .filter(choice => choice.phone_number !== ownNumber)
        .forEach(choice => {
          const name = choice.friendly_name;
          const showName = name && name !== choice.phone_number;
          options.push({
            value: choice.phone_number,
            label: showName
              ? `${choice.phone_number} · ${name}`
              : choice.phone_number,
          });
        });
      const isListed = options.some(
        option => option.value === this.voiceCallerId
      );
      if (!isListed) {
        options.push({
          value: this.voiceCallerId,
          label: this.voiceCallerId,
        });
      }
      return options;
    },
    isSubmitDisabled() {
      if (!this.voiceEnabled) return false;
      if (this.needsCredentials) {
        if (this.needsApiKeySid && !this.apiKeySid) return true;
        return !this.apiKeySecret;
      }
      return false;
    },
  },
  watch: {
    'inbox.voice_enabled'(val) {
      this.voiceEnabled = val || false;
      if (val && !this.isWhatsApp) this.loadCallerIds();
    },
    'inbox.api_key_sid'(val) {
      this.apiKeySid = val || '';
    },
    'inbox.inbound_calls_enabled'(val) {
      this.inboundCallsEnabled = val !== false;
    },
    'inbox.ring_timeout_seconds'(val) {
      this.ringTimeoutSeconds = val || 30;
    },
    'inbox.max_wait_seconds'(val) {
      this.maxWaitSeconds = val || 300;
    },
    'inbox.voice_language_menu_enabled'(val) {
      this.voiceLanguageMenuEnabled = val || false;
    },
    'inbox.voice_caller_id'(val) {
      this.voiceCallerId = val || '';
    },
  },
  mounted() {
    if (this.inbox.voice_enabled && !this.isWhatsApp) this.loadCallerIds();
  },
  methods: {
    async loadCallerIds() {
      this.isLoadingCallerIds = true;
      this.callerIdsLoadFailed = false;
      try {
        const { data } = await VoiceCallerIdsAPI.get(this.inbox.id);
        this.callerIdChoices = data.payload;
      } catch (_) {
        this.callerIdsLoadFailed = true;
      } finally {
        this.isLoadingCallerIds = false;
      }
    },
    async handleInboundToggle(newValue) {
      if (this.isTogglingInbound) return;
      const previousValue = this.inboundCallsEnabled;
      this.inboundCallsEnabled = newValue;
      this.isTogglingInbound = true;
      try {
        await InboxesAPI.setInboundCalls(this.inbox.id, newValue);
        await this.$store.dispatch('inboxes/get', this.inbox.id);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (_) {
        this.inboundCallsEnabled = previousValue;
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isTogglingInbound = false;
      }
    },
    async updateVoiceSettings() {
      this.isUpdating = true;
      try {
        const channelPayload = {
          voice_enabled: this.voiceEnabled,
          ring_timeout_seconds: Number(this.ringTimeoutSeconds) || 30,
          max_wait_seconds: Number(this.maxWaitSeconds) || 300,
          voice_language_menu_enabled: this.voiceLanguageMenuEnabled,
        };

        if (!this.isWhatsApp) {
          channelPayload.voice_caller_id = this.voiceCallerId;
        }

        if (this.needsCredentials) {
          if (this.needsApiKeySid) {
            channelPayload.api_key_sid = this.apiKeySid;
          }
          channelPayload.api_key_secret = this.apiKeySecret;
        }

        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id,
          formData: false,
          channel: channelPayload,
        });
        this.apiKeySecret = '';
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(error.message || this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdating = false;
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <SettingsToggleSection
      v-model="voiceEnabled"
      :header="$t('INBOX_MGMT.VOICE_CONFIGURATION.ENABLE_VOICE.LABEL')"
      :description="voiceDescription"
    />

    <div v-if="voiceEnabled && needsCredentials" class="flex flex-col gap-4">
      <p class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.VOICE_CONFIGURATION.CREDENTIALS.DESCRIPTION') }}
      </p>
      <NextInput
        v-if="needsApiKeySid"
        v-model="apiKeySid"
        :label="$t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SID.LABEL')"
        :placeholder="$t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SID.PLACEHOLDER')"
      />
      <NextInput
        v-model="apiKeySecret"
        type="password"
        :label="$t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SECRET.LABEL')"
        :placeholder="
          $t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SECRET.PLACEHOLDER')
        "
      />
    </div>

    <div
      v-if="inbox.voice_enabled"
      class="relative"
      :class="{ 'pointer-events-none opacity-60': isTogglingInbound }"
    >
      <SettingsToggleSection
        :model-value="inboundCallsEnabled"
        :header="$t('INBOX_MGMT.VOICE_CONFIGURATION.INBOUND.LABEL')"
        :description="inboundDescription"
        :hide-toggle="isTogglingInbound"
        @update:model-value="handleInboundToggle"
      >
        <template v-if="isTogglingInbound" #hiddenToggle>
          <Spinner class="size-4 text-n-slate-11" />
        </template>
      </SettingsToggleSection>
    </div>

    <div
      v-if="inbox.voice_enabled && inbox.voice_call_webhook_url && !isWhatsApp"
    >
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_VOICE_URL_TITLE')"
        :help-text="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_VOICE_URL_SUBTITLE')
        "
      >
        <woot-code :script="inbox.voice_call_webhook_url" lang="html" />
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_STATUS_URL_TITLE')
        "
        :help-text="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_STATUS_URL_SUBTITLE')
        "
      >
        <woot-code :script="inbox.voice_status_webhook_url" lang="html" />
      </SettingsFieldSection>
    </div>

    <div v-if="inbox.voice_enabled" class="flex flex-col gap-4">
      <SettingsFieldSection
        v-if="!isWhatsApp"
        :label="$t('INBOX_MGMT.VOICE_CONFIGURATION.CALLER_ID.LABEL')"
        :help-text="$t('INBOX_MGMT.VOICE_CONFIGURATION.CALLER_ID.DESCRIPTION')"
      >
        <div class="flex items-center gap-3">
          <NextSelect
            v-model="voiceCallerId"
            :options="callerIdOptions"
            :disabled="isLoadingCallerIds"
            :aria-label="$t('INBOX_MGMT.VOICE_CONFIGURATION.CALLER_ID.LABEL')"
          />
          <Spinner v-if="isLoadingCallerIds" class="size-4 text-n-slate-11" />
        </div>
        <p v-if="callerIdsLoadFailed" class="mt-2 mb-0 text-sm text-n-ruby-11">
          {{ $t('INBOX_MGMT.VOICE_CONFIGURATION.CALLER_ID.LOAD_ERROR') }}
          <button type="button" class="underline" @click="loadCallerIds">
            {{ $t('INBOX_MGMT.VOICE_CONFIGURATION.CALLER_ID.RETRY') }}
          </button>
        </p>
      </SettingsFieldSection>
      <SettingsToggleSection
        v-model="voiceLanguageMenuEnabled"
        :header="$t('INBOX_MGMT.VOICE_CONFIGURATION.LANGUAGE_MENU.LABEL')"
        :description="
          $t('INBOX_MGMT.VOICE_CONFIGURATION.LANGUAGE_MENU.DESCRIPTION')
        "
      />
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.VOICE_CONFIGURATION.RING_TIMEOUT.LABEL')"
        :help-text="
          $t('INBOX_MGMT.VOICE_CONFIGURATION.RING_TIMEOUT.DESCRIPTION')
        "
      >
        <NextInput
          v-model="ringTimeoutSeconds"
          type="number"
          :placeholder="
            $t('INBOX_MGMT.VOICE_CONFIGURATION.RING_TIMEOUT.PLACEHOLDER')
          "
        />
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.VOICE_CONFIGURATION.MAX_WAIT.LABEL')"
        :help-text="$t('INBOX_MGMT.VOICE_CONFIGURATION.MAX_WAIT.DESCRIPTION')"
      >
        <NextInput
          v-model="maxWaitSeconds"
          type="number"
          :placeholder="
            $t('INBOX_MGMT.VOICE_CONFIGURATION.MAX_WAIT.PLACEHOLDER')
          "
        />
      </SettingsFieldSection>
    </div>

    <div>
      <NextButton
        :disabled="isSubmitDisabled"
        :is-loading="isUpdating"
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
        @click="updateVoiceSettings"
      />
    </div>
  </div>
</template>
