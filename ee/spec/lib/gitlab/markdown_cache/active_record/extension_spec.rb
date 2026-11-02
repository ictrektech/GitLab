# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MarkdownCache::ActiveRecord::Extension, feature_category: :wiki do
  describe 'storing mentions on #refresh_markdown_cache!' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, :with_namespace) }
    let_it_be(:other_user) { create(:user, :with_namespace) }

    context 'for a note on a vulnerability' do
      let(:note) do
        created = create(:note_on_vulnerability, project: project, note: "hey @#{user.username}")
        created.update_columns(cached_markdown_version: nil)

        Note.find(created.id)
      end

      def mentioned_users_ids
        VulnerabilityUserMention.where(note_id: note.id).pick(:mentioned_users_ids)
      end

      it 'writes the mentions' do
        VulnerabilityUserMention.where(note_id: note.id).delete_all

        note.refresh_markdown_cache!

        expect(mentioned_users_ids).to eq([user.id])
      end

      context 'when the note has been edited since it was loaded' do
        before do
          Note.find(note.id).update!(note: "hey @#{other_user.username}")
        end

        it 'keeps the mentions from the edit' do
          note.refresh_markdown_cache!

          expect(mentioned_users_ids).to eq([other_user.id])
        end
      end
    end
  end
end
