<script>
import { GlCard, GlSprintf } from '@gitlab/ui';
import { formatDate } from '~/lib/utils/datetime/date_format_utility';
import { formatNumber } from '../../../usage_billing/utils';

export default {
  name: 'UsageStatisticsCards',
  components: {
    GlCard,
    GlSprintf,
  },
  props: {
    totalUsedCredits: {
      type: Number,
      required: true,
    },
    dailyAverage: {
      type: Number,
      required: true,
    },
    peakDayUsage: {
      type: Number,
      required: true,
    },
    peakDayDate: {
      type: String,
      required: true,
    },
  },
  methods: {
    formatNumber,
    formatDate,
  },
};
</script>

<template>
  <div class="gl-grid gl-grid-cols-1 gl-gap-4 @md/panel:gl-grid-cols-3">
    <gl-card class="gl-flex-1" data-testid="range-total-usage-card">
      <template #header>
        <h2 class="gl-heading-scale-500 gl-mb-0">
          {{ s__('UsageBilling|Total usage') }}
        </h2>
      </template>
      <template #default>
        <div class="gl-text-sm gl-text-subtle">
          <gl-sprintf
            :message="
              n__('UsageBilling|%{count} credit', 'UsageBilling|%{count} credits', totalUsedCredits)
            "
          >
            <template #count>
              <span class="gl-heading-scale-600 gl-block">{{
                formatNumber(totalUsedCredits)
              }}</span>
            </template>
          </gl-sprintf>
        </div>
      </template>
    </gl-card>
    <gl-card class="gl-flex-1" data-testid="daily-average-card">
      <template #header>
        <h2 class="gl-heading-scale-500 gl-mb-0">
          {{ s__('UsageBilling|Daily average usage') }}
        </h2>
      </template>
      <template #default>
        <div class="gl-text-sm gl-text-subtle">
          <gl-sprintf
            :message="
              n__('UsageBilling|%{count} credit', 'UsageBilling|%{count} credits', dailyAverage)
            "
          >
            <template #count>
              <span class="gl-heading-scale-600 gl-block">{{ formatNumber(dailyAverage) }}</span>
            </template>
          </gl-sprintf>
        </div>
      </template>
    </gl-card>
    <gl-card class="gl-flex-1" data-testid="peak-day-usage-card">
      <template #header>
        <h2 class="gl-heading-scale-500 gl-mb-0">
          {{ s__('UsageBilling|Peak day usage') }}
        </h2>
      </template>
      <template #default>
        <div class="gl-text-sm gl-text-subtle">
          <gl-sprintf
            v-if="peakDayDate"
            :message="
              n__(
                'UsageBilling|%{count} credit on %{date}',
                'UsageBilling|%{count} credits on %{date}',
                peakDayUsage,
              )
            "
          >
            <template #count>
              <span class="gl-heading-scale-600 gl-block">{{ formatNumber(peakDayUsage) }}</span>
            </template>
            <template #date>{{ formatDate(peakDayDate, 'mmm d', true) }}</template>
          </gl-sprintf>
          <gl-sprintf
            v-else
            :message="
              n__('UsageBilling|%{count} credit', 'UsageBilling|%{count} credits', peakDayUsage)
            "
          >
            <template #count>
              <span class="gl-heading-scale-600 gl-block">{{ formatNumber(peakDayUsage) }}</span>
            </template>
          </gl-sprintf>
        </div>
      </template>
    </gl-card>
  </div>
</template>
