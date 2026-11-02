# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventsHelper, feature_category: :user_profile do
  describe '#event_note_target_url' do
    subject { helper.event_note_target_url(event) }

    context 'for epic note events' do
      let(:group) { build_stubbed(:group, :public) }
      let(:event) { build_stubbed(:event, group: group, project: nil) }

      it 'returns an epic url' do
        event.target = build_stubbed(:note_on_epic, note: 'foo')

        expect(subject).to match("#{group.to_param}/-/epics/#{event.note_target.iid}#note_#{event.target.id}")
      end
    end

    context 'for vulnerability events' do
      let(:project) { build_stubbed(:project) }
      let(:note) { build_stubbed(:note_on_vulnerability, note: 'comment') }
      let(:event) { build_stubbed(:event, project: project, target: note) }

      it 'returns an appropriate URL' do
        path = "#{project.full_path}/-/security/vulnerabilities/#{event.note_target.id}"
        fragment = "note_#{event.target.id}"

        expect(subject).to match("#{path}##{fragment}")
      end
    end
  end

  describe '#event_wiki_page_target_url' do
    let_it_be(:group) { create(:group) }

    context 'for group wiki' do
      let_it_be_with_refind(:wiki_page_meta) { create(:wiki_page_meta, :for_wiki_page, container: group) }

      let(:event) { build_stubbed(:event, target: wiki_page_meta, group: wiki_page_meta.namespace, project: nil) }

      it 'links to the wiki page' do
        url = helper.group_wiki_url(wiki_page_meta.namespace, wiki_page_meta.canonical_slug)

        expect(helper.event_wiki_page_target_url(event)).to eq(url)
      end

      context 'without canonical slug' do
        before do
          event.target.slugs.update_all(canonical: false)
          event.target.clear_memoization(:canonical_slug)
        end

        it 'links to the home page' do
          url = helper.group_wiki_url(wiki_page_meta.namespace, Wiki::HOMEPAGE)

          expect(helper.event_wiki_page_target_url(event)).to eq(url)
        end
      end
    end
  end
end
