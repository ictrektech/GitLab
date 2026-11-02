# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Emails::AdminNotification, feature_category: :insider_threat do
  include EmailSpec::Matchers
  include_context 'gitlab email notification'

  describe 'user_auto_banned_email' do
    let_it_be(:alerted_user) { create(:user) }
    let_it_be(:alerted_user_id) { alerted_user.id }
    let_it_be(:user) { create(:user) }

    let(:max_project_downloads) { 5 }
    let(:time_period) { 600 }
    let(:auto_ban_enabled) { true }
    let(:group) { nil }
    let(:ip_address) { '192.0.2.1' }

    subject(:mail) do
      Notify.user_auto_banned_email(
        alerted_user_id, user.id,
        max_project_downloads: max_project_downloads,
        within_seconds: time_period,
        auto_ban_enabled: auto_ban_enabled,
        group: group,
        ip_address: ip_address
      )
    end

    shared_examples 'a plain-text email with an unpunctuated URL' do
      it 'includes the URL without trailing punctuation in the plain-text email' do
        body = subject.text_part.body.decoded

        expect(body).to include(url)
        expect(body).not_to match(/#{Regexp.escape(url)}[.,;:!?]/)
      end
    end

    it_behaves_like 'an email sent from GitLab'
    it_behaves_like 'it should not have Gmail Actions links'
    it_behaves_like 'a user cannot unsubscribe through footer link'
    it_behaves_like 'appearance header and footer enabled'
    it_behaves_like 'appearance header and footer not enabled'

    it 'is sent to the alerted user' do
      is_expected.to deliver_to alerted_user.email
    end

    it 'has the correct subject' do
      is_expected.to have_subject "We've detected unusual activity"
    end

    it 'includes the reason' do
      is_expected.to have_body_text "We want to let you know #{user.name} has exceeded the Git rate limit due to them \
        downloading more than 5 project repositories within 10 minutes."
    end

    it 'includes the IP address of the request in both parts' do
      expect(mail.html_part.body.decoded)
        .to include('The request that exceeded the rate limit came from IP address 192.0.2.1.')
      expect(mail.text_part.body.decoded)
        .to include('The request that exceeded the rate limit came from IP address 192.0.2.1.')
    end

    context 'when the IP address is not available' do
      let(:ip_address) { nil }

      it 'does not mention an IP address' do
        expect(mail.html_part.body.decoded).not_to include('IP address')
        expect(mail.text_part.body.decoded).not_to include('IP address')
      end
    end

    context 'when threshold is 1 and interval is 1 minute' do
      let(:max_project_downloads) { 1 }
      let(:time_period) { 60 }

      it 'uses singular form' do
        is_expected.to have_body_text "1 project repository within 1 minute."
      end
    end

    context 'when interval is less than a minute' do
      let(:time_period) { 30 }

      it 'uses the correct unit' do
        is_expected.to have_body_text "5 project repositories within 30 seconds."
      end
    end

    it 'includes the scope of the ban' do
      is_expected.to have_body_text "Because you enabled auto-banning, we have also automatically banned this user \
        from your GitLab instance"
    end

    it 'includes a link to unban the user' do
      is_expected.to have_body_text admin_users_url(filter: 'banned')
    end

    it_behaves_like 'a plain-text email with an unpunctuated URL' do
      let(:url) { admin_users_url(filter: 'banned') }
    end

    it 'includes a link to change the settings' do
      is_expected.to have_body_text reporting_admin_application_settings_url
    end

    it_behaves_like 'a plain-text email with an unpunctuated URL' do
      let(:url) { reporting_admin_application_settings_url }
    end

    it 'includes the email reason' do
      is_expected.to have_body_text %r{You're receiving this email because of your account on <a .*>localhost<\/a>}
    end

    context 'when auto-ban is disabled' do
      let(:auto_ban_enabled) { false }

      it 'does not include the scope of the ban' do
        is_expected.not_to have_body_text "Because you enabled auto-banning, we have also automatically banned this \
          user from your GitLab instance"
      end

      it 'does not include a link to unban the user' do
        is_expected.not_to have_body_text admin_users_url(filter: 'banned')
      end
    end

    context 'when scoped to a group' do
      let(:group) { build_stubbed(:group) }

      it 'includes the scope of the ban' do
        is_expected.to have_body_text "Because you enabled auto-banning, we have also automatically banned this user \
          from your group (#{group.name})"
      end

      it 'includes a link to unban the user' do
        is_expected.to have_body_text group_group_members_url(group, tab: 'banned')
      end

      it_behaves_like 'a plain-text email with an unpunctuated URL' do
        let(:url) { group_group_members_url(group, tab: 'banned') }
      end

      it 'includes a link to change the settings' do
        is_expected.to have_body_text group_settings_reporting_url(group)
      end

      it_behaves_like 'a plain-text email with an unpunctuated URL' do
        let(:url) { group_settings_reporting_url(group) }
      end
    end

    context 'when alerted user does not exist anymore' do
      let_it_be(:alerted_user_id) { non_existing_record_id }

      it_behaves_like 'no email is sent'
    end
  end

  describe 'namespace_storage_usage_csv_email' do
    let(:user) { build_stubbed(:admin) }
    let(:csv_data) { CSV.parse_line("a,b,c\nd,e,f") }

    subject(:email) { Notify.namespace_storage_usage_csv_email(user, csv_data) }

    it { expect(email.subject).to eq('Exported namespace storage usage') }
    it { expect(email.to).to contain_exactly(user.notification_email_or_default) }
    it { expect(email.html_part).to have_content('Your CSV export of namespace storage usage') }
    it { expect(email.text_part).to have_content('Your CSV export of namespace storage usage') }

    it 'contains a CSV attachment', :freeze_time do
      expect(email.attachments.size).to eq(1)
      expect(email.attachments[0].content_type).to eq('text/csv')
      expect(email.attachments[0].filename).to eq("namespace-storage-usage-#{Time.current.to_fs(:number)}.csv")
    end
  end
end
