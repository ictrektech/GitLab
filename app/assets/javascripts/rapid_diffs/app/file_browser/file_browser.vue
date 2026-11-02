<script>
import { mapState } from 'pinia';
import DiffsFileTree from '~/diffs/components/diffs_file_tree.vue';
import { useDiffsList } from '~/rapid_diffs/stores/diffs_list';
import { useFileBrowser } from '~/diffs/stores/file_browser';
import { useDiffsView } from '~/rapid_diffs/stores/diffs_view';

export default {
  name: 'FileBrowser',
  components: {
    DiffsFileTree,
  },
  props: {
    groupBlobsListItems: {
      type: Boolean,
      required: false,
      default: true,
    },
    linkedFilePath: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['click-file'],
  computed: {
    ...mapState(useDiffsView, ['totalFilesCount', 'singleFileMode', 'currentDiffFileHash']),
    ...mapState(useDiffsList, ['loadedFiles']),
    ...mapState(useFileBrowser, ['fileBrowserVisible']),
    treeLoadedFiles() {
      return this.singleFileMode ? null : this.loadedFiles;
    },
  },
  methods: {
    clickFile(file) {
      this.$emit('click-file', file);
    },
    selectFile(file) {
      useDiffsView().setCurrentFile(file.fileHash);
    },
    toggleFolder(path) {
      useFileBrowser().toggleTreeOpen(path);
    },
  },
};
</script>

<template>
  <diffs-file-tree
    v-if="fileBrowserVisible"
    floating-resize
    :loaded-files="treeLoadedFiles"
    :total-files-count="totalFilesCount"
    :group-blobs-list-items="groupBlobsListItems"
    :current-diff-file-id="currentDiffFileHash"
    :linked-file-path="linkedFilePath"
    @click-file="clickFile"
    @select-file="selectFile"
    @toggle-folder="toggleFolder"
  />
</template>
