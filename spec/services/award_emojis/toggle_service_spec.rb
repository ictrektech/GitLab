# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AwardEmojis::ToggleService, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }
  let_it_be_with_reload(:awardable) { create(:note, project: project) }

  let(:name) { AwardEmoji::THUMBS_UP }

  subject(:service) { described_class.new(awardable, name, user) }

  def names_awarded_by(awarded_by)
    awardable.award_emoji.awarded_by(awarded_by).pluck(:name)
  end

  describe '#execute' do
    context 'when user has awarded an emoji' do
      let!(:award_from_other_user) { create(:award_emoji, name: name, awardable: awardable, user: create(:user)) }
      let!(:award) { create(:award_emoji, name: name, awardable: awardable, user: user) }

      it 'calls AwardEmojis::DestroyService' do
        expect(AwardEmojis::AddService).not_to receive(:new)

        expect_next_instance_of(AwardEmojis::DestroyService) do |service|
          expect(service).to receive(:execute)
        end

        service.execute
      end

      it 'destroys an AwardEmoji' do
        expect { service.execute }.to change { AwardEmoji.count }.by(-1)
      end

      it 'returns the result of DestroyService#execute' do
        mock_result = double(foo: true)

        expect_next_instance_of(AwardEmojis::DestroyService) do |service|
          expect(service).to receive(:execute).and_return(mock_result)
        end

        result = service.execute

        expect(result).to eq(mock_result)
      end
    end

    context 'when user has not awarded an emoji' do
      it 'calls AwardEmojis::AddService' do
        expect_next_instance_of(AwardEmojis::AddService) do |service|
          expect(service).to receive(:execute)
        end

        expect(AwardEmojis::DestroyService).not_to receive(:new)

        service.execute
      end

      it 'creates an AwardEmoji' do
        expect { service.execute }.to change { AwardEmoji.count }.by(1)
      end

      it 'returns the result of AddService#execute' do
        mock_result = double(foo: true)

        expect_next_instance_of(AwardEmojis::AddService) do |service|
          expect(service).to receive(:execute).and_return(mock_result)
        end

        result = service.execute

        expect(result).to eq(mock_result)
      end
    end

    context 'when user has awarded the same skin tone' do
      let(:name) { 'thumbsup_tone1' }

      let!(:award) { create(:award_emoji, name: name, awardable: awardable, user: user) }

      it 'removes it' do
        expect(AwardEmojis::AddService).not_to receive(:new)

        expect { service.execute }.to change { AwardEmoji.count }.by(-1)
        expect(names_awarded_by(user)).to be_empty
      end
    end

    context 'when user has awarded another skin tone of the same emoji' do
      let(:name) { 'thumbsup_tone1' }

      let!(:existing_award) { create(:award_emoji, name: 'thumbsup_tone3', awardable: awardable, user: user) }

      # AwardEmojis::AddService owns the replacement; this only checks that toggling reaches it.
      it 'replaces the existing tone through AwardEmojis::AddService' do
        expect_next_instance_of(AwardEmojis::AddService, awardable, name, user) do |add_service|
          expect(add_service).to receive(:execute).and_call_original
        end

        result = service.execute

        expect(result[:status]).to eq(:success)
        expect(names_awarded_by(user)).to contain_exactly(name)
      end
    end
  end
end
