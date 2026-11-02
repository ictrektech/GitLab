# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::ExternallyStoredField, feature_category: :team_planning do
  before_all do
    ActiveRecord::Schema.define do
      create_table :_test_externally_stored_field_parents, force: true do |t|
        t.timestamps null: false
      end

      create_table :_test_externally_stored_fields, force: true do |t|
        t.references :parent, foreign_key: { to_table: :_test_externally_stored_field_parents }
        t.integer :content_file_store, limit: 2, null: false, default: 1
        t.text :content_file
        t.integer :summary_file_store, limit: 2, null: false, default: 1
        t.text :summary_file
        t.integer :cached_markdown_version
        t.text :description
        t.text :description_html
        t.timestamps null: false
      end
    end
  end

  after(:all) do
    ActiveRecord::Schema.define do
      drop_table :_test_externally_stored_fields, force: true
      drop_table :_test_externally_stored_field_parents, force: true
    end
  end

  let(:uploader_class) do
    Class.new(GitlabUploader) do
      include ObjectStorage::Concern
      storage_location :uploads

      def store_dir
        '_test_externally_stored_fields'
      end
    end
  end

  let(:model_class) do
    uploader = uploader_class
    Class.new(ApplicationRecord) do
      self.table_name = '_test_externally_stored_fields'

      include Gitlab::ExternallyStoredField

      externally_stored_field :content
      mount_external_storage uploader

      def self.name
        'TestExternallyStoredModel'
      end
    end
  end

  let(:parent_class) do
    child_class = model_class
    Class.new(ApplicationRecord) do
      self.table_name = '_test_externally_stored_field_parents'

      has_one :child, anonymous_class: child_class, foreign_key: :parent_id, inverse_of: :parent, autosave: true

      def self.name
        'TestExternallyStoredParent'
      end
    end
  end

  before do
    p_class = parent_class
    model_class.reset_column_information
    model_class.belongs_to :parent, anonymous_class: p_class, foreign_key: :parent_id, inverse_of: :child,
      optional: true
  end

  describe 'virtual attribute accessors' do
    it 'defines reader, writer, and changed? methods' do
      instance = model_class.new

      expect(instance).to respond_to(:content)
      expect(instance).to respond_to(:content=)
      expect(instance).to respond_to(:content_changed?)
    end

    it 'tracks changes to virtual attributes' do
      instance = model_class.new

      expect(instance.content_changed?).to be false

      instance.content = 'new value'
      expect(instance.content_changed?).to be true
      expect(instance.content).to eq('new value')
    end
  end

  describe 'changed_attributes integration' do
    it 'includes virtual field changes in changed_attributes' do
      instance = model_class.new
      instance.content = 'test'

      attrs = instance.send(:changed_attributes)
      expect(attrs).to have_key('content')
    end

    it 'does not include unchanged virtual fields' do
      instance = model_class.new

      attrs = instance.send(:changed_attributes)
      expect(attrs).not_to have_key('content')
    end
  end

  describe 'lazy loading' do
    let(:stored) do
      instance = model_class.create!
      instance.content = 'stored'
      instance.save!

      model_class.find(instance.id)
    end

    it 'does not read from storage until a field is accessed' do
      expect(stored).not_to receive(:read_external_payload)

      stored.id
    end

    it 'reads from storage once however many times a field is accessed' do
      expect(stored).to receive(:read_external_payload).once.and_call_original

      stored.content
      stored.content
    end
  end

  describe 'persistence' do
    it 'stores and retrieves field values via object storage' do
      instance = model_class.create!
      instance.content = 'round trip'
      instance.save!

      reloaded = model_class.find(instance.id)
      expect(reloaded.content).to eq('round trip')
    end

    it 'reads back as nil when the stored document is not valid JSON' do
      instance = model_class.create!
      instance.content = 'round trip'
      instance.save!
      File.write(instance.content_file.path, 'this is not json')

      expect(model_class.find(instance.id).content).to be_nil
    end

    it 'does not ask the store to delete a document that is not there' do
      instance = model_class.create!
      instance.content = 'temporary'
      instance.save!

      reloaded = model_class.find(instance.id)
      expect(reloaded.content).to eq('temporary')
      FileUtils.rm(reloaded.content_file.path)

      expect(reloaded).not_to receive(:remove_content_file!)

      reloaded.content = nil
      reloaded.save!

      expect(reloaded.reload[:content_file]).to be_nil
    end

    it 'updates stored values on save' do
      instance = model_class.create!
      instance.content = 'original'
      instance.save!

      instance.content = 'modified'
      instance.save!

      reloaded = model_class.find(instance.id)
      expect(reloaded.content).to eq('modified')
    end

    it 'clears change tracking after persist' do
      instance = model_class.create!
      instance.content = 'test'
      instance.save!

      expect(instance.changes).to be_empty
    end

    it 'names the document after the payload' do
      instance = model_class.create!
      instance.content = 'named'
      instance.save!

      expect(instance.reload[:content_file]).to eq('content.json')
    end

    it 'keeps writing to the stored document name when it differs from the current default' do
      instance = model_class.create!
      instance.content = 'legacy'
      instance.save!
      stored_dir = File.dirname(instance.content_file.path)
      FileUtils.mv(instance.content_file.path, File.join(stored_dir, 'legacy-name.json'))
      instance.update_column(:content_file, 'legacy-name.json')

      reloaded = model_class.find(instance.id)
      expect(reloaded.content).to eq('legacy')

      reloaded.content = 'still legacy'
      reloaded.save!

      expect(reloaded.reload[:content_file]).to eq('legacy-name.json')
      expect(File.exist?(File.join(stored_dir, 'content.json'))).to be false
      expect(model_class.find(instance.id).content).to eq('still legacy')
    end
  end

  describe 'blank payloads' do
    let(:markdown_class) do
      uploader = uploader_class
      Class.new(ApplicationRecord) do
        self.table_name = '_test_externally_stored_fields'

        include CacheMarkdownField
        cache_markdown_field :content, storage: :external
        mount_external_storage uploader

        def self.name
          'TestBlankPayloadModel'
        end
      end
    end

    before do
      stub_commonmark_sourcepos_disabled
    end

    it 'stores nothing for a record created with no field values' do
      instance = markdown_class.create!

      expect(instance[:content_file]).to be_nil
    end

    it 'does not ask the store to remove a payload that was never written' do
      instance = markdown_class.new

      expect(instance).not_to receive(:remove_content_file!)

      instance.save!
    end

    it 'removes the stored payload when every field is cleared' do
      instance = markdown_class.create!(content: 'temporary')

      stored_path = instance.content_file.path
      expect(File.exist?(stored_path)).to be true

      instance.update!(content: nil)

      expect(File.exist?(stored_path)).to be false
      expect(instance.reload[:content_file]).to be_nil
    end

    it 'reads back as nil after clearing' do
      instance = markdown_class.create!(content: 'temporary')
      instance.update!(content: nil)

      expect(markdown_class.find(instance.id).content).to be_nil
    end

    it 'stores a payload again when a cleared field is repopulated' do
      instance = markdown_class.create!(content: 'first')
      instance.update!(content: nil)
      instance.update!(content: 'second')

      expect(markdown_class.find(instance.id).content).to eq('second')
    end

    it 'does not ask the store to delete a document that was never written' do
      instance = markdown_class.create!
      instance.update_column(:content_file, 'content.json')
      instance.update_column(:cached_markdown_version, 0)

      reloaded = markdown_class.find(instance.id)
      expect(reloaded).not_to receive(:remove_content_file!)

      reloaded.refresh_markdown_cache!

      expect(reloaded.reload[:content_file]).to be_nil
    end
  end

  describe 'cleanup on destroy' do
    it 'removes the stored file' do
      instance = model_class.create!
      instance.content = 'doomed'
      instance.save!

      stored_path = instance.content_file.path
      expect(File.exist?(stored_path)).to be true

      instance.destroy!

      expect(File.exist?(stored_path)).to be false
    end

    it 'reports a failing removal instead of raising out of the committed destroy' do
      instance = model_class.create!
      instance.content = 'doomed'
      instance.save!

      error = RuntimeError.new('object storage is down')
      allow(instance).to receive(:remove_content_file!).and_raise(error)
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)

      expect { instance.destroy! }.not_to raise_error
      expect(model_class).not_to exist(instance.id)
    end
  end

  describe '#[]' do
    it 'returns the externally stored field value' do
      instance = model_class.create!
      instance.content = 'bracket access'
      instance.save!

      reloaded = model_class.find(instance.id)
      expect(reloaded[:content]).to eq('bracket access')
    end

    it 'falls through to super for AR attributes' do
      instance = model_class.create!

      expect(instance[:content_file_store]).to eq(1)
    end
  end

  describe 'setter tracks changes against stored value' do
    it 'detects change when setting nil on a field with a stored value without reading first' do
      instance = model_class.create!
      instance.content = 'previously stored'
      instance.save!

      reloaded = model_class.find(instance.id)
      reloaded.content = nil

      expect(reloaded.content_changed?).to be true
    end
  end

  describe '.externally_stored_payloads' do
    it 'maps each payload to the fields it holds' do
      expect(model_class.externally_stored_payloads).to eq(content: Set[:content])
    end
  end

  describe '.mount_external_storage' do
    it 'rejects a mount declared before any externally stored field' do
      uploader = uploader_class

      expect do
        Class.new(ApplicationRecord) do
          self.table_name = '_test_externally_stored_fields'

          include Gitlab::ExternallyStoredField

          mount_external_storage uploader
        end
      end.to raise_error(ArgumentError, /must come last/)
    end
  end

  describe 'one payload per field' do
    let(:split_class) do
      uploader = uploader_class
      Class.new(ApplicationRecord) do
        self.table_name = '_test_externally_stored_fields'

        include Gitlab::ExternallyStoredField

        externally_stored_field :content
        externally_stored_field :summary
        mount_external_storage uploader

        def self.name
          'TestSplitPayloadModel'
        end
      end
    end

    it 'gives each payload its own column and document' do
      instance = split_class.create!(content: 'in content', summary: 'in summary')

      expect(instance.reload[:content_file]).to eq('content.json')
      expect(instance[:summary_file]).to eq('summary.json')
      expect(Gitlab::Json::SafeParser.parse(instance.content_file.read)).to eq('content' => 'in content')
      expect(Gitlab::Json::SafeParser.parse(instance.summary_file.read)).to eq('summary' => 'in summary')
    end

    it 'does not read a payload to serve a field from another payload' do
      instance = split_class.create!(content: 'in content', summary: 'in summary')
      reloaded = split_class.find(instance.id)

      expect(reloaded).to receive(:read_external_payload).with(:content).once.and_call_original
      expect(reloaded).not_to receive(:read_external_payload).with(:summary)

      expect(reloaded.content).to eq('in content')
    end

    it 'does not rewrite a payload whose fields did not change' do
      instance = split_class.create!(content: 'in content', summary: 'in summary')
      instance.reload

      expect(instance).to receive(:persist_external_payload).with(:content).and_call_original
      expect(instance).not_to receive(:persist_external_payload).with(:summary)

      instance.content = 'changed'
      instance.save!
    end

    it 'reports storage per payload' do
      instance = split_class.create!(content: 'in content')

      expect(instance.reload.external_payload_stored?(:content)).to be true
      expect(instance.external_payload_stored?(:summary)).to be false
    end

    it 'leaves the other payload alone when one is cleared' do
      instance = split_class.create!(content: 'in content', summary: 'in summary')

      instance.content = nil
      instance.save!

      reloaded = split_class.find(instance.id)
      expect(reloaded.content).to be_nil
      expect(reloaded.summary).to eq('in summary')
      expect(reloaded.external_payload_stored?(:content)).to be false
    end
  end

  describe 'autosave compatibility' do
    it 'persists externally stored field changes when saved via parent autosave' do
      parent = parent_class.create!
      child = model_class.create!(parent: parent, content: 'original')
      parent.reload

      parent.child.content = 'updated via autosave'
      parent.save!

      reloaded = model_class.find(child.id)
      expect(reloaded.content).to eq('updated via autosave')
    end
  end

  describe 'reload' do
    it 'clears cached externally stored field values so they are re-read from storage' do
      instance = model_class.create!
      instance.content = 'before reload'
      instance.save!

      expect(instance.content).to eq('before reload')

      other_ref = model_class.find(instance.id)
      other_ref.content = 'after external update'
      other_ref.save!

      instance.reload
      expect(instance.content).to eq('after external update')
    end
  end

  describe 'mixed AR and external storage with CacheMarkdownField' do
    let(:mixed_class) do
      uploader = uploader_class
      Class.new(ApplicationRecord) do
        self.table_name = '_test_externally_stored_fields'

        include CacheMarkdownField
        cache_markdown_field :description
        cache_markdown_field :content, storage: :external
        mount_external_storage uploader

        def self.name
          'TestMixedStorageModel'
        end
      end
    end

    let(:reverse_order_class) do
      uploader = uploader_class
      Class.new(ApplicationRecord) do
        self.table_name = '_test_externally_stored_fields'

        include CacheMarkdownField
        cache_markdown_field :content, storage: :external
        cache_markdown_field :description
        mount_external_storage uploader

        def self.name
          'TestReverseOrderMixedStorageModel'
        end
      end
    end

    before do
      stub_commonmark_sourcepos_disabled
    end

    it 'registers AR fields as non-external and external fields as external' do
      instance = mixed_class.new

      expect(instance.externally_stored_field?(:description)).to be false
      expect(instance.externally_stored_field?(:description_html)).to be false
      expect(instance.externally_stored_field?(:content)).to be true
      expect(instance.externally_stored_field?(:content_html)).to be true
    end

    it 'keeps the rendered HTML in the same payload as its markdown field' do
      expect(mixed_class.externally_stored_payloads).to eq(content: Set[:content, :content_html])
    end

    it 'round-trips both field types through create and reload' do
      instance = mixed_class.new(description: '**bold description**')
      instance.content = '`code content`'
      instance.save!

      reloaded = mixed_class.find(instance.id)
      expect(reloaded.description).to eq('**bold description**')
      expect(reloaded.description_html).to include('<strong>')
      expect(reloaded.content).to eq('`code content`')
      expect(reloaded.content_html).to include('<code>')
    end

    it 'stores description_html in the DB column and content_html in the object store blob' do
      instance = mixed_class.new(description: '**db**')
      instance.content = '**blob**'
      instance.save!

      reloaded = mixed_class.find(instance.id)

      expect(reloaded.read_attribute(:description_html)).to include('<strong>')
      expect(mixed_class.column_names).not_to include('content_html')
      expect(reloaded.content_html).to include('<strong>')
    end

    it 'shares a single cached_markdown_version across both field types' do
      instance = mixed_class.new(description: 'a')
      instance.content = 'b'
      instance.save!

      reloaded = mixed_class.find(instance.id)
      expect(reloaded.cached_markdown_version).to eq(Gitlab::MarkdownCache::CACHE_COMMONMARK_VERSION_SHIFTED)
    end

    it 'tracks changes independently per storage type' do
      instance = mixed_class.create!(description: 'original description')
      instance.content = 'original content'
      instance.save!

      reloaded = mixed_class.find(instance.id)

      reloaded.description = 'new description'
      expect(reloaded.markdown_field_changed?(:description)).to be true
      expect(reloaded.markdown_field_changed?(:content)).to be false

      reloaded2 = mixed_class.find(instance.id)

      reloaded2.content = 'new content'
      expect(reloaded2.markdown_field_changed?(:description)).to be false
      expect(reloaded2.markdown_field_changed?(:content)).to be true
    end

    it 'updates both field types independently' do
      instance = mixed_class.new(description: 'description v1')
      instance.content = 'content v1'
      instance.save!

      instance.description = 'description v2'
      instance.save!

      reloaded = mixed_class.find(instance.id)
      expect(reloaded.description).to eq('description v2')
      expect(reloaded.content).to eq('content v1')

      instance.content = 'content v2'
      instance.save!

      reloaded = mixed_class.find(instance.id)
      expect(reloaded.description).to eq('description v2')
      expect(reloaded.content).to eq('content v2')
    end

    it 'works regardless of declaration order' do
      instance = reverse_order_class.new(description: '**reversed**')
      instance.content = '`also reversed`'
      instance.save!

      reloaded = reverse_order_class.find(instance.id)
      expect(reloaded.description).to eq('**reversed**')
      expect(reloaded.description_html).to include('<strong>')
      expect(reloaded.content).to eq('`also reversed`')
      expect(reloaded.content_html).to include('<code>')

      expect(reloaded.externally_stored_field?(:description)).to be false
      expect(reloaded.externally_stored_field?(:content)).to be true
    end

    it 'refreshes the markdown cache into the field\'s own payload' do
      instance = mixed_class.create!(description: 'a')
      instance.content = 'stale'
      instance.save!
      instance.update_column(:cached_markdown_version, 0)

      mixed_class.find(instance.id).refresh_markdown_cache!

      expect(mixed_class.find(instance.id).content_html).to include('stale')
    end

    it 'does not rewrite the payload when a cache refresh renders the same HTML' do
      instance = mixed_class.create!(description: 'a')
      instance.content = 'unchanging'
      instance.save!
      instance.update_column(:cached_markdown_version, 0)

      reloaded = mixed_class.find(instance.id)
      expect(reloaded).not_to receive(:write_external_payload)

      reloaded.refresh_markdown_cache!
    end
  end

  describe 'with object storage enabled and direct upload' do
    before do
      stub_object_storage_uploader(
        config: Gitlab.config.uploads.object_store,
        uploader: uploader_class,
        enabled: true,
        direct_upload: true
      )
    end

    it 'persists the payload store as REMOTE when saving with object storage configured' do
      instance = model_class.create!
      instance.content = 'goes remote'
      instance.save!

      expect(instance.reload[:content_file_store]).to eq(ObjectStorage::Store::REMOTE)
    end

    it 'reads content from remote storage when the payload store is REMOTE' do
      instance = model_class.create!
      payload = { 'content' => 'lives remote' }

      uploader = uploader_class.new(instance, :content_file)
      uploader.store!(CarrierWaveStringFile.new(Gitlab::Json.dump(payload)))
      instance.update_columns(content_file: uploader.filename, content_file_store: ObjectStorage::Store::REMOTE)

      reloaded = model_class.find(instance.id)
      expect(reloaded.content).to eq('lives remote')
    end

    it 'returns nil for missing remote blob without raising' do
      instance = model_class.create!
      instance.update_column(:content_file_store, ObjectStorage::Store::REMOTE)

      reloaded = model_class.find(instance.id)

      expect { reloaded.content }.not_to raise_error
      expect(reloaded.content).to be_nil
    end

    it 'does not overwrite the payload store on an unrelated save' do
      instance = model_class.create!
      instance.content = 'stored remotely'
      instance.save!

      expect(instance.reload[:content_file_store]).to eq(ObjectStorage::Store::REMOTE)

      # Simulate config change: direct upload disabled between saves
      stub_object_storage_uploader(
        config: Gitlab.config.uploads.object_store,
        uploader: uploader_class,
        enabled: true,
        direct_upload: false
      )

      # Save an unrelated attribute; content_file_store must not change.
      instance.update!(description: 'unrelated change')

      expect(instance.reload[:content_file_store]).to eq(ObjectStorage::Store::REMOTE)
    end

    it 'raises on save once object storage is disabled but a payload is already remote' do
      instance = model_class.create!
      instance.content = 'stored remotely'
      instance.save!
      instance.reload

      stub_object_storage_uploader(
        config: Gitlab.config.uploads.object_store,
        uploader: uploader_class,
        enabled: false
      )

      expect { instance.update!(description: 'unrelated change') }
        .to raise_error(RuntimeError, /Object Storage is not enabled/)
    end
  end
end
