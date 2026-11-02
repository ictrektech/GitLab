# frozen_string_literal: true

require_relative '../../../../../tooling/lib/tooling/fe_test_janitor/example_parser'

RSpec.describe Tooling::FeTestJanitor::ExampleParser, feature_category: :tooling do
  let(:parser) { described_class.new(source) }

  describe '#parse' do
    subject(:parse) { parser.parse }

    context 'with a simple it block' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            it 'does something' do
              expect(true).to be true
            end
          end
        RUBY
      end

      it 'finds one example' do
        examples = parse
        expect(examples.size).to eq(1)
      end

      it 'captures the description' do
        example = parse.first
        expect(example.description).to eq('does something')
      end

      it 'captures the line number' do
        example = parse.first
        expect(example.line_number).to eq(2)
      end

      it 'captures the body' do
        example = parse.first
        expect(example.body).to include('expect(true).to be true')
      end
    end

    context 'with multiple examples' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Bar' do
            it 'first example' do
              sign_in(user)
            end

            it 'second example' do
              expect(page).to have_css('[data-testid="foo"]')
            end
          end
        RUBY
      end

      it 'finds two examples' do
        expect(parse.size).to eq(2)
      end

      it 'assigns correct line numbers' do
        examples = parse
        expect(examples[0].line_number).to eq(2)
        expect(examples[1].line_number).to eq(6)
      end
    end

    context 'with it_behaves_like' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Baz' do
            it_behaves_like 'work items title'
            it_behaves_like 'work items description'
          end
        RUBY
      end

      it 'finds two shared examples' do
        expect(parse.size).to eq(2)
      end

      it 'captures the shared example description' do
        examples = parse
        expect(examples[0].description).to eq('work items title')
        expect(examples[1].description).to eq('work items description')
      end

      it 'marks the calls as shared' do
        expect(parse.map(&:shared)).to all(be(true))
      end
    end

    context 'with a shared example call that takes a block of examples' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Jobs' do
            it_behaves_like 'job page responds with status', 200 do
              it 'renders job details' do
                expect(page).to have_content(job.name)
              end
            end
          end
        RUBY
      end

      it 'finds the shared call and the example inside its block' do
        examples = parse

        expect(examples.map(&:description)).to match_array(['job page responds with status', 'renders job details'])
        expect(examples.map(&:shared)).to match_array([true, false])
      end
    end

    context 'with an if block inside an example' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            it 'signs in when needed' do
              if needs_sign_in
                sign_in(user)
              end

              expect(page).to have_css('[data-testid="foo"]')
            end
          end
        RUBY
      end

      it 'keeps the lines after the if block in the body' do
        expect(parse.first.body).to include('have_css')
      end
    end

    context 'with `do` inside a string' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            it 'hides the to-do button' do
              expect(page).not_to have_button('Add a to-do item')
            end

            it 'shows the award button' do
              expect(page).to have_selector('[data-testid="award-button"]')
            end
          end
        RUBY
      end

      it 'ends the example at its own end' do
        examples = parse

        expect(examples.size).to eq(2)
        expect(examples.first.body).not_to include('have_selector')
      end
    end

    context 'with `end` inside a string' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            it 'moves to end of list' do
              click_button 'Move to end of list'

              expect(page).to have_selector('.board-card:last-child')
            end
          end
        RUBY
      end

      it 'keeps the lines after the string in the body' do
        expect(parse.first.body).to include('have_selector')
      end
    end

    context 'with a parenthesised description and a brace block' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            it('is allowed for admin', :enable_admin_mode) { is_expected.to be_allowed_for(:admin) }
          end
        RUBY
      end

      it 'finds the example' do
        examples = parse

        expect(examples.size).to eq(1)
        expect(examples.first.description).to eq('is allowed for admin')
      end
    end

    context 'with an interpolated description' do
      let(:source) do
        <<~'RUBY'
          RSpec.describe 'Foo' do
            it "shows #{label}" do
              expect(page).to have_content(label)
            end
          end
        RUBY
      end

      it 'keeps the interpolation in the description' do
        expect(parse.first.description).to eq('shows #{label}') # rubocop:disable Lint/InterpolationCheck -- the parser keeps the source text
      end
    end

    context 'with examples that have no description' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            it { is_expected.to be_allowed_for(:admin) }

            specify do
              expect(page).to have_css('[data-testid="foo"]')
            end
          end
        RUBY
      end

      it 'finds both examples and labels them by line' do
        expect(parse.map(&:description))
          .to match_array(['(no description, line 2)', '(no description, line 4)'])
      end
    end

    context 'with nested contexts' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Nested' do
            context 'outer' do
              context 'inner' do
                it 'nested example' do
                  sign_in(user)
                end
              end
            end
          end
        RUBY
      end

      it 'finds the nested example' do
        examples = parse
        expect(examples.size).to eq(1)
        expect(examples.first.description).to eq('nested example')
      end
    end

    context 'with a multi-line it header (quarantine tag)' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Quarantined' do
            it 'shows widget',
              quarantine: 'https://gitlab.com/issues/123' do
              within_testid('work-item-development') do
                expect(page).to have_css('[data-testid="item"]')
              end
            end
          end
        RUBY
      end

      it 'finds one example' do
        expect(parse.size).to eq(1)
      end

      it 'captures the description without trailing comma' do
        expect(parse.first.description).to eq('shows widget')
      end

      it 'includes the quarantine tag and inner body in the collected lines' do
        expect(parse.first.body).to include('quarantine:', 'have_css')
      end
    end

    context 'with shared example definitions' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            shared_examples 'a widget' do
              it 'shows the widget' do
                expect(page).to have_css('[data-testid="widget"]')
              end
            end

            shared_context 'with a signed in user' do
              it 'signs in' do
                sign_in(user)
              end
            end

            it 'renders the page' do
              expect(page).to have_content('Foo')
            end

            it_behaves_like 'a widget'
          end
        RUBY
      end

      it 'skips the examples inside the definitions' do
        expect(parse.map(&:description)).to contain_exactly('renders the page', 'a widget')
      end
    end

    context 'with invalid Ruby' do
      let(:source) do
        <<~RUBY
          RSpec.describe 'Foo' do
            it 'shows the widget' do
              expect(page).to have_css('[data-testid="widget"]')
          end
        RUBY
      end

      it 'raises a ParseError with the line of each error' do
        expect { parse }.to raise_error(described_class::ParseError, /line \d+: /)
      end
    end
  end
end
