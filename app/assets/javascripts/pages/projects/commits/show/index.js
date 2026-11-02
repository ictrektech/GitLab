import { addShortcutsExtension } from '~/behaviors/shortcuts';
import ShortcutsNavigation from '~/behaviors/shortcuts/shortcuts_navigation';
import initAmbiguousRefModal from '~/vue_shared/components/ref/init_ambiguous_ref_modal';
import initCommitListApp from '~/projects/commits/init_commit_list_app';

initCommitListApp();

addShortcutsExtension(ShortcutsNavigation);
initAmbiguousRefModal();
