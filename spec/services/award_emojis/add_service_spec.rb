# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AwardEmojis::AddService, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:awardable, freeze: false) { create(:note, project: project) }

  let(:name) { AwardEmoji::THUMBS_UP }

  subject(:service) { described_class.new(awardable, name, user) }

  def names_awarded_by(awarded_by)
    awardable.award_emoji.awarded_by(awarded_by).pluck(:name)
  end

  describe '#execute' do
    context 'when user is not authorized' do
      it 'does not add an emoji' do
        expect { service.execute }.not_to change { AwardEmoji.count }
      end

      it 'returns an error state' do
        result = service.execute

        expect(result[:status]).to eq(:error)
        expect(result[:http_status]).to eq(:forbidden)
      end
    end

    context 'when user is authorized' do
      before_all do
        project.add_developer(user)
      end

      it 'creates an award emoji' do
        expect { service.execute }.to change { AwardEmoji.count }.by(1)
      end

      it 'returns the award emoji' do
        result = service.execute

        expect(result[:award]).to be_kind_of(AwardEmoji)
      end

      it 'return a success status' do
        result = service.execute

        expect(result[:status]).to eq(:success)
      end

      it 'sets the correct properties on the award emoji' do
        award = service.execute[:award]

        expect(award.name).to eq(name)
        expect(award.user).to eq(user)
      end

      it 'executes hooks' do
        expect(service).to receive(:execute_hooks).with(kind_of(AwardEmoji), 'award')

        service.execute
      end

      describe 'marking Todos as done' do
        subject { service.execute }

        include_examples 'creating award emojis marks Todos as done'
      end

      context 'when the awardable cannot have emoji awarded to it' do
        before do
          expect(awardable).to receive(:emoji_awardable?).and_return(false)
        end

        it 'does not add an emoji' do
          expect { service.execute }.not_to change { AwardEmoji.count }
        end

        it 'returns an error status' do
          result = service.execute

          expect(result[:status]).to eq(:error)
          expect(result[:http_status]).to eq(:unprocessable_entity)
        end
      end

      context 'when the awardable is invalid' do
        before do
          expect_next_instance_of(AwardEmoji) do |award|
            expect(award).to receive(:valid?).and_return(false)
            expect(award).to receive_message_chain(:errors, :full_messages).and_return(['Error 1', 'Error 2'])
          end
        end

        it 'does not add an emoji' do
          expect { service.execute }.not_to change { AwardEmoji.count }
        end

        it 'returns an error status' do
          result = service.execute

          expect(result[:status]).to eq(:error)
        end

        it 'returns an error message' do
          result = service.execute

          expect(result[:message]).to eq('Error 1 and Error 2')
        end
      end

      context 'when the user has awarded another skin tone of the same emoji' do
        let(:name) { 'thumbsup_tone1' }
        let(:existing_name) { 'thumbsup_tone3' }

        let!(:existing_award) { create(:award_emoji, name: existing_name, awardable: awardable, user: user) }

        it 'replaces the existing tone with the added one' do
          result = service.execute

          expect(result[:status]).to eq(:success)
          expect(result[:award]).to have_attributes(name: name, user: user)
          expect(names_awarded_by(user)).to contain_exactly(name)
        end

        it 'removes the existing tone through AwardEmojis::DestroyService' do
          expect_next_instance_of(AwardEmojis::DestroyService, awardable, existing_name, user) do |destroy_service|
            expect(destroy_service).to receive(:execute).and_call_original
          end

          service.execute
        end

        context 'when creating the award fails' do
          before do
            expect_next_instance_of(AwardEmoji) do |award|
              expect(award).to receive(:valid?).and_return(false)
              expect(award).to receive_message_chain(:errors, :full_messages).and_return(['Error 1'])
            end
          end

          it 'keeps the existing tone' do
            expect(AwardEmojis::DestroyService).not_to receive(:new)

            result = service.execute

            expect(result[:status]).to eq(:error)
            expect(names_awarded_by(user)).to contain_exactly(existing_name)
          end
        end

        it 'removes every other tone the user holds' do
          create(:award_emoji, name: 'thumbsup', awardable: awardable, user: user)

          service.execute

          expect(names_awarded_by(user)).to contain_exactly(name)
        end

        it 'keeps the tones awarded by other users' do
          other_user = create(:user)
          create(:award_emoji, name: existing_name, awardable: awardable, user: other_user)

          service.execute

          expect(names_awarded_by(other_user)).to contain_exactly(existing_name)
        end

        it 'keeps the tones of other emoji' do
          create(:award_emoji, name: 'thumbsdown_tone3', awardable: awardable, user: user)

          service.execute

          expect(names_awarded_by(user)).to contain_exactly(name, 'thumbsdown_tone3')
        end

        context 'with the plain emoji and both tone naming schemes' do
          using RSpec::Parameterized::TableSyntax

          where(:existing_name, :name) do
            'thumbsup_tone3'                       | 'thumbsup'
            'thumbsup'                             | 'thumbsup_tone2'
            'people_holding_hands_light_skin_tone' | 'people_holding_hands_dark_skin_tone'
          end

          with_them do
            it 'replaces the existing tone with the added one' do
              service.execute

              expect(names_awarded_by(user)).to contain_exactly(name)
            end
          end
        end

        context 'when the emoji_skin_tone_preference feature flag is disabled' do
          before do
            stub_feature_flags(emoji_skin_tone_preference: false)
          end

          it 'adds the new tone next to the existing one' do
            expect(AwardEmojis::DestroyService).not_to receive(:new)

            service.execute

            expect(names_awarded_by(user)).to contain_exactly(existing_name, name)
          end
        end
      end

      context 'when the added emoji has no skin tone group' do
        using RSpec::Parameterized::TableSyntax

        let!(:existing_award) { create(:award_emoji, name: existing_name, awardable: awardable, user: user) }

        # Plain emoji, unmapped tones and two-tone emoji have no base, so nothing else is removed.
        where(:existing_name, :name) do
          [
            %w[thumbsup_tone3 rocket],
            %w[rocket tada],
            %w[man_in_tuxedo_light_skin_tone man_in_tuxedo_dark_skin_tone],
            %w[
              couple_with_heart_man_man_dark_skin_tone_light_skin_tone
              couple_with_heart_man_man_light_skin_tone_dark_skin_tone
            ]
          ]
        end

        with_them do
          it 'adds it and keeps the existing reaction' do
            expect(AwardEmojisFinder).not_to receive(:new)
            expect(AwardEmojis::DestroyService).not_to receive(:new)

            service.execute

            expect(names_awarded_by(user)).to contain_exactly(existing_name, name)
          end
        end
      end
    end
  end
end
