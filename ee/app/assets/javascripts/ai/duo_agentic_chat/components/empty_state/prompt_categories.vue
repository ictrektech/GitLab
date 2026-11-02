<script>
import { GlButton, GlCollapsibleListbox, GlIcon } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import ScrollScrim from '~/vue_shared/components/scroll_scrim/scroll_scrim.vue';
import { PROMPT_CATEGORY_ICONS, DEFAULT_CATEGORY_ICON } from '../../constants';

const categoryIcon = (key) => PROMPT_CATEGORY_ICONS[key] ?? DEFAULT_CATEGORY_ICON;

export default {
  name: 'PromptCategories',
  components: {
    GlButton,
    GlCollapsibleListbox,
    GlIcon,
    ScrollScrim,
  },
  props: {
    /**
     * Categories of suggested prompts, `{ key, title, contextual, questions }`,
     * as returned by the aiChatContextPresets questionCategories field.
     */
    categories: {
      type: Array,
      required: true,
    },
    /**
     * Key of the category selected by default. The default follows this prop
     * until the user picks a category themselves.
     */
    initialExpandedKey: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['select'],
  data() {
    return {
      userSelectedKey: null,
    };
  },
  computed: {
    // Switching agent swaps the category list, so a key the user picked
    // earlier can disappear. Fall back rather than render an empty card.
    selectedCategory() {
      return (
        this.findCategory(this.userSelectedKey) ??
        this.findCategory(this.initialExpandedKey) ??
        null
      );
    },
    selectedKey() {
      return this.selectedCategory?.key ?? null;
    },
    categoryItems() {
      return this.categories.map((category) => ({
        value: category.key,
        text: category.title,
        icon: categoryIcon(category.key),
      }));
    },
    toggleText() {
      return this.selectedCategory?.title ?? s__('DuoAgenticChat|Select category');
    },
    toggleIcon() {
      return this.selectedCategory ? categoryIcon(this.selectedCategory.key) : '';
    },
    listLabel() {
      return sprintf(s__('DuoAgenticChat|Suggestions for %{category}'), {
        category: this.selectedCategory.title,
      });
    },
    // Selecting a category returns focus to the dropdown toggle, so the list
    // swapping underneath is silent without this.
    selectionAnnouncement() {
      if (!this.selectedCategory) {
        return '';
      }
      const count = this.selectedCategory.questions.length;
      return sprintf(
        n__(
          'DuoAgenticChat|%{count} suggestion for %{category}',
          'DuoAgenticChat|%{count} suggestions for %{category}',
          count,
        ),
        { count, category: this.selectedCategory.title },
      );
    },
  },
  methods: {
    findCategory(key) {
      return this.categories.find((category) => category.key === key);
    },
  },
};
</script>

<template>
  <div>
    <div class="gl-mb-3 gl-flex gl-items-center gl-justify-between gl-gap-3">
      <h3 class="gl-mb-0 gl-mt-0 gl-shrink-0 gl-text-base gl-font-normal gl-text-subtle">
        {{ s__('DuoAgenticChat|Suggestions') }}
      </h3>
      <!-- min-w-0 so an agent with a long name truncates instead of pushing
      the toggle past the panel edge; flex items refuse to shrink without it. -->
      <gl-collapsible-listbox
        class="gl-min-w-0"
        :items="categoryItems"
        :selected="selectedKey"
        :toggle-text="toggleText"
        :icon="toggleIcon"
        category="tertiary"
        size="small"
        toggle-class="gl-max-w-full gl-truncate"
        data-testid="prompt-category-dropdown"
        @select="userSelectedKey = $event"
      >
        <template #list-item="{ item }">
          <span class="gl-flex gl-items-center gl-gap-3">
            <gl-icon :name="item.icon" />
            {{ item.text }}
          </span>
        </template>
      </gl-collapsible-listbox>
    </div>
    <!-- Capped and scrollable: an agent can define far more questions than the
    static categories, which otherwise grows the card past the panel. ScrollScrim
    fades the clipped edge, and only once there is something clipped. -->
    <scroll-scrim v-if="selectedCategory" class="gl-max-h-37 gl-rounded-xl gl-bg-strong">
      <ul
        :aria-label="listLabel"
        class="gl-mb-0 gl-flex gl-list-none gl-flex-col gl-gap-2 gl-p-2"
        data-testid="prompt-category-card"
      >
        <li v-for="(question, index) in selectedCategory.questions" :key="`prompt-${index}`">
          <gl-button
            category="tertiary"
            block
            class="!gl-justify-start !gl-py-2 gl-text-left"
            size="small"
            data-testid="prompt-category-question"
            @click="$emit('select', question)"
          >
            <span class="gl-whitespace-normal gl-leading-20">{{ question }}</span>
          </gl-button>
        </li>
      </ul>
    </scroll-scrim>
    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="prompt-category-announcement"
      >{{ selectionAnnouncement }}</span
    >
  </div>
</template>
