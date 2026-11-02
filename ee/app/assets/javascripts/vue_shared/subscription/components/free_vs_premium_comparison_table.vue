<script>
import { GlButton, GlIcon, GlLink, GlPopover, GlSprintf } from '@gitlab/ui';
import { __ } from '~/locale';

export default {
  name: 'FreeVsPremiumComparisonTable',
  components: {
    GlButton,
    GlIcon,
    GlLink,
    GlPopover,
    GlSprintf,
  },
  props: {
    // { id, title, freeIncluded, ...popover fields }; Premium is always included.
    rows: {
      type: Array,
      required: true,
    },
    showFeaturePopovers: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['popover-shown', 'popover-click'],
  i18n: {
    free: __('Free'),
    premium: __('Premium'),
    included: __('Included'),
    notIncluded: __('Not included'),
    learnMore: __('Learn more'),
  },
  methods: {
    rowElementId(id) {
      return `${id}FreeVsPremiumComparisonTable`;
    },
    isRowLinked(row) {
      return this.showFeaturePopovers && Boolean(row.docsLink);
    },
    rowHeightClass(index) {
      return index === 0 ? 'gl-h-12' : 'gl-h-11';
    },
    includedText(included) {
      return included ? this.$options.i18n.included : this.$options.i18n.notIncluded;
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-px-3 gl-pb-4 gl-pt-6">
    <div class="gl-mt-1 gl-flex gl-basis-3/5 gl-flex-col">
      <div class="gl-h-9"></div>

      <div
        v-for="(row, index) in rows"
        :key="rowElementId(row.id)"
        class="gl-border-t gl-flex gl-items-center sm:gl-h-9"
        :class="rowHeightClass(index)"
      >
        <template v-if="isRowLinked(row)">
          <span :id="rowElementId(row.id)" class="gl-ml-5 gl-underline">{{ row.title }}</span>

          <gl-popover
            :target="rowElementId(row.id)"
            :title="row.title"
            show-close-button
            @shown="$emit('popover-shown', row.id)"
          >
            <gl-sprintf
              v-if="row.descriptionWithCreditsLink"
              :message="row.descriptionWithCreditsLink"
            >
              <template #creditsLink="{ content }">
                <gl-link :href="row.docsLink" target="_blank">{{ content }}</gl-link>
              </template>
            </gl-sprintf>
            <template v-else>{{ row.descriptionWithoutCredits || row.description }}</template>

            <gl-button
              v-if="!row.hideButton"
              target="_blank"
              data-testid="comparison-table-popover-button"
              class="gl-mt-3 gl-w-full"
              :href="row.purchaseCreditsUrl || row.docsLink"
              variant="confirm"
              @click="$emit('popover-click', row.id)"
            >
              {{ row.buttonText || $options.i18n.learnMore }}
            </gl-button>
          </gl-popover>
        </template>
        <span v-else class="gl-ml-5">{{ row.title }}</span>
      </div>
    </div>

    <div class="gl-mt-1 gl-flex gl-basis-1/5 gl-flex-col gl-text-center" data-testid="free-column">
      <div class="gl-flex gl-h-9 gl-items-center gl-justify-center gl-font-bold">
        {{ $options.i18n.free }}
      </div>

      <div
        v-for="(row, index) in rows"
        :key="`${rowElementId(row.id)}-free`"
        class="gl-border-t gl-flex gl-items-center gl-justify-center sm:gl-h-9"
        :class="rowHeightClass(index)"
      >
        <gl-icon :name="row.freeIncluded ? 'check' : 'close'" />
        <span class="gl-sr-only">{{ includedText(row.freeIncluded) }}</span>
      </div>
    </div>

    <div
      class="free-vs-premium-gradient-border gl-border gl-flex gl-basis-1/5 gl-flex-col gl-text-center"
      data-testid="premium-column"
    >
      <div class="gl-mx-3 gl-flex gl-h-9 gl-items-center gl-justify-center gl-font-bold">
        {{ $options.i18n.premium }}
      </div>

      <div
        v-for="(row, index) in rows"
        :key="`${rowElementId(row.id)}-premium`"
        class="gl-border-t gl-flex gl-items-center gl-justify-center sm:gl-h-9"
        :class="rowHeightClass(index)"
      >
        <gl-icon name="check" />
        <span class="gl-sr-only">{{ $options.i18n.included }}</span>
      </div>
    </div>
  </div>
</template>

<style>
.free-vs-premium-gradient-border {
  border: 2px solid transparent;
  border-radius: 0.5rem;
  background-origin: border-box;
  background-clip: content-box, border-box;
  background-image:
    linear-gradient(var(--gl-background-color-overlap)),
    linear-gradient(to bottom, #ff31e0, #c80043);
}
</style>
