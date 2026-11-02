# frozen_string_literal: true

require_relative '../../../../../tooling/lib/tooling/fe_test_janitor/classifier'

RSpec.describe Tooling::FeTestJanitor::Classifier, feature_category: :tooling do
  let(:classifier) { described_class.new }
  let(:example_struct) { Tooling::FeTestJanitor::ExampleParser::Example }

  def make_example(body, description: 'example', line_number: 1)
    example_struct.new(description: description, line_number: line_number, body: body)
  end

  describe '#classify' do
    subject(:classify) { classifier.classify(example) }

    context 'with a shared example call' do
      let(:example) do
        example_struct.new(
          description: 'drag and drop', line_number: 1, body: "it_behaves_like 'drag_to'\n", shared: true
        )
      end

      it 'returns :shared without matching signals' do
        expect(classify.verdict).to eq(:shared)
        expect(classify.reasons).to match_array(['shared example call, not analyzed'])
      end
    end

    context 'with only keep signals' do
      let(:example) do
        make_example <<~RUBY
          sign_in(user)
          visit project_work_item_path(project, work_item.iid)
          find('.item').drag_to(find('.target'))
        RUBY
      end

      it 'returns :keep for a drag-and-drop interaction' do
        expect(classify.verdict).to eq(:keep)
        expect(classify.reasons).to include(match(/drag-and-drop/))
      end
    end

    context 'with a service object call split across lines' do
      let(:example) do
        make_example <<~RUBY
          WorkItems::UpdateService.new(
            container: project
          ).execute(work_item)
          expect(page).to have_content('Updated')
        RUBY
      end

      it 'returns :keep' do
        expect(classify.verdict).to eq(:keep)
        expect(classify.reasons).to include('service object call')
      end
    end

    context 'with a quarantine tag' do
      let(:example) do
        make_example <<~RUBY
          it 'shows widget', quarantine: 'https://gitlab.com/issues/123' do
            within_testid('work-item-development') do
              expect(page).to have_css('[data-testid="item"]')
            end
          end
        RUBY
      end

      it 'returns :migrate' do
        expect(classify.verdict).to eq(:migrate)
        expect(classify.reasons).to include(match(/quarantine/))
      end
    end

    context 'with have_css on a data-testid' do
      let(:example) do
        make_example <<~RUBY
          within_testid('work-item-tree') do
            expect(page).to have_css('[data-testid="add-tree-form"]')
          end
        RUBY
      end

      it 'returns :migrate' do
        expect(classify.verdict).to eq(:migrate)
      end
    end

    context 'when the example signs in and uses FactoryBot records' do
      let(:example) do
        make_example <<~RUBY
          sign_in(user)
          create(:note, noteable: work_item)
          visit project_work_item_path(project, work_item.iid)
          expect(page).to have_css('[data-testid="note"]')
        RUBY
      end

      it 'returns :migrate' do
        expect(classify.verdict).to eq(:migrate)
      end
    end

    context 'when the example asserts DB state after a UI action' do
      let(:example) do
        make_example <<~RUBY
          click_button 'Close'
          expect(work_item.reload.state).to eq('closed')
        RUBY
      end

      it 'returns :reframe' do
        expect(classify.verdict).to eq(:reframe)
        expect(classify.reasons).to include(match(/reloads a record/))
      end
    end

    context 'with reframe and UI assertion signals' do
      let(:example) do
        make_example <<~RUBY
          expect { click_button 'Comment' }.to change { Note.count }.by(1)
          expect(page).to have_css('[data-testid="note"]')
        RUBY
      end

      it 'returns :reframe over :migrate' do
        expect(classify.verdict).to eq(:reframe)
      end
    end

    context 'with reframe and keep signals' do
      let(:example) do
        make_example <<~RUBY
          perform_enqueued_jobs { click_button 'Export' }
          expect(project.reload.export_file).to be_present
        RUBY
      end

      it 'returns :keep' do
        expect(classify.verdict).to eq(:keep)
      end
    end

    context 'with keep and migrate signals' do
      let(:example) do
        make_example <<~RUBY
          visit project_work_item_path(project, work_item.iid)
          attach_file('upload', file_path)
          within_testid('work-item-relationships') do
            expect(page).to have_css('[data-testid="work-item-show-closed"]')
          end
        RUBY
      end

      it 'returns :partial' do
        expect(classify.verdict).to eq(:partial)
        expect(classify.reasons).to include(match(/file upload/), match(/have_css/))
      end
    end

    context 'with no signals' do
      let(:example) { make_example("expect(page).to have_content('hello')\n") }

      it 'defaults to :keep' do
        expect(classify.verdict).to eq(:keep)
        expect(classify.reasons).to be_empty
      end
    end
  end
end
