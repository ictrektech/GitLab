import initSettingsPanels from '~/settings_panels';
import { initTestModelConfiguration } from './test_model_configuration';
import { initUpdateEmbeddingsRequestBatchSize } from './update_embeddings_request_batch_size';

export const initSemanticSearchEmbeddings = () => {
  initSettingsPanels();
  initTestModelConfiguration();
  initUpdateEmbeddingsRequestBatchSize();
};
