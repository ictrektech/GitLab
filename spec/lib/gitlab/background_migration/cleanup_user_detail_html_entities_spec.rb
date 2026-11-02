# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::CleanupUserDetailHtmlEntities, feature_category: :user_profile do
  let(:users) { table(:users) }
  let(:user_details) { table(:user_details) }
  let(:organizations) { table(:organizations) }

  let(:organization) { organizations.create!(name: 'organization', path: 'organization') }
  let(:sub_batch_size) { 100 }

  subject(:migration) do
    described_class.new(
      start_cursor: [user_details.minimum(:user_id)],
      end_cursor: [user_details.maximum(:user_id)],
      batch_table: :user_details,
      batch_column: :user_id,
      sub_batch_size: sub_batch_size,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    )
  end

  def create_user_detail(**attributes)
    user = users.create!(
      projects_limit: 0, email: "user#{users.count}@example.com", organization_id: organization.id
    )

    user_details.create!(user_id: user.id, **attributes)
  end

  describe '#perform' do
    using RSpec::Parameterized::TableSyntax

    context 'with a decodable value' do
      let!(:user_detail) { create_user_detail(column => input) }

      where(:column, :input, :expected) do
        :linkedin    | 'a&amp;b'                               | 'a&b'
        :website_url | 'a&#38;b'                               | 'a&b'
        :twitter     | 'a&#x26;b'                              | 'a&b'
        :github      | 'a&#X26;b'                              | 'a&b'
        :bluesky     | 'a&quot;b'                              | 'a"b'
        :discord     | 'a&apos;b'                              | "a'b"
        :mastodon    | '&#233;'                                | 'é'
        :orcid       | 'a&amp;amp;b'                           | 'a&b'
        :linkedin    | '&lt;x&gt;'                             | ''
        :linkedin    | '&lt;b&gt;x'                            | 'x'
        :linkedin    | 'a &gt; b'                              | 'a > b'
        :linkedin    | 'a &lt;3 b'                             | 'a <3 b'
        :linkedin    | '&lt;script&gt;alert(1)&lt;/script&gt;' | ''
        :website_url | 'https://example.com&amp;'              | 'https://example.com&'
      end

      with_them do
        it 'writes a value that a profile save accepts and keeps' do
          migration.perform

          value = user_detail.reload[column]
          expect(value).to eq(expected)
          expect(CGI.unescapeHTML(value)).to eq(value)
          expect(CGI.unescapeHTML(Sanitize.fragment(value))).to eq(value)
          expect { Gitlab::PathTraversal.check_path_traversal!(value) }.not_to raise_error
        end
      end
    end

    context 'with a value that needs no change' do
      let!(:user_detail) { create_user_detail(linkedin: input) }

      where(:input) { ['a&b', 'A&AMP;B', 'a&nbsp;b', '', '%2e%2e/x', 'a%2525b'] }

      with_them do
        it 'leaves the value unchanged and logs nothing' do
          expect(::Gitlab::BackgroundMigration::Logger).not_to receive(:warn)

          expect { migration.perform }.not_to change { user_detail.reload.linkedin }
        end
      end
    end

    context 'with a value that must not be written' do
      let!(:user_detail) { create_user_detail(column => input) }

      where(:column, :input, :reason) do
        :linkedin    | 'a&#0;b'                           | 'control_character'
        :linkedin    | 'a&#10;b'                          | 'control_character'
        :linkedin    | 'a&#1;b'                           | 'control_character'
        :linkedin    | '&#55296;'                         | 'invalid_encoding'
        :linkedin    | 'a%ff&amp;b'                       | 'invalid_encoding'
        :linkedin    | "a&#{'amp;' * 12}b"                | 'escaped_html_entities'
        :website_url | '&#106;avascript:alert(1)'         | 'invalid_url_scheme'
        :linkedin    | '&#46;&#46;/x'                     | 'path_traversal'
        :linkedin    | '%2e%2e/x&amp;'                    | 'path_traversal'
        :linkedin    | 'a%2525b&amp;'                     | 'double_encoding'
      end

      with_them do
        it 'leaves the value unchanged and logs the reason without the value' do
          expect(::Gitlab::BackgroundMigration::Logger).to receive(:warn).once.with(
            :message => 'CleanupUserDetailHtmlEntities skipped value',
            Labkit::Fields::GL_USER_ID => user_detail.user_id,
            :column => column.to_s,
            :skip_reason => reason
          )

          expect { migration.perform }.not_to change { user_detail.reload[column] }
        end
      end
    end

    context 'with a sub-batch smaller than the batch' do
      let(:sub_batch_size) { 1 }

      it 'reads each skipped value once' do
        create_user_detail(linkedin: '&#46;&#46;/x')
        create_user_detail(linkedin: 'plain')
        create_user_detail(linkedin: 'plain')

        expect(::Gitlab::BackgroundMigration::Logger).to receive(:warn).once

        migration.perform
      end
    end

    it 'fixes other rows in the sub-batch when one value is skipped' do
      skipped = create_user_detail(linkedin: 'a&#0;b')
      fixed = create_user_detail(linkedin: 'a&amp;b')

      migration.perform

      expect(skipped.reload.linkedin).to eq('a&#0;b')
      expect(fixed.reload.linkedin).to eq('a&b')
    end

    it 'fixes several columns of one row' do
      user_detail = create_user_detail(linkedin: 'a&amp;b', twitter: 'c&amp;d', github: 'plain')

      migration.perform

      expect(user_detail.reload).to have_attributes(linkedin: 'a&b', twitter: 'c&d', github: 'plain')
    end

    it 'does not change columns outside the sanitizable fields' do
      user_detail = create_user_detail(linkedin: 'a&amp;b', location: 'a&amp;b', company: 'a&amp;b')

      migration.perform

      expect(user_detail.reload).to have_attributes(linkedin: 'a&b', location: 'a&amp;b', company: 'a&amp;b')
    end

    it 'is idempotent' do
      user_detail = create_user_detail(linkedin: 'a&amp;amp;b', twitter: '&#46;&#46;/x')

      migration.perform

      expect { migration.perform }.not_to change { user_detail.reload.attributes }
    end

    it 'does not overwrite a value changed after it was read' do
      user_detail = create_user_detail(linkedin: 'a&amp;b')
      edited = false

      # Simulates a concurrent profile edit between the candidate SELECT and the guarded UPDATE.
      callback = ->(*, payload) do
        next if edited || !payload[:sql].match?(/\ASELECT .* ~ /)

        edited = true
        user_details.where(user_id: user_detail.user_id).update_all(linkedin: 'edited')
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { migration.perform }

      expect(user_detail.reload.linkedin).to eq('edited')
    end
  end
end
