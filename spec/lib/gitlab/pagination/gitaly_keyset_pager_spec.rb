# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Pagination::GitalyKeysetPager, feature_category: :source_code_management do
  let(:pager) { described_class.new(request_context, project) }

  let_it_be(:project) { create(:project, :small_repo) }

  let(:request_context) { double("request context") }
  let(:finder) { double("branch finder") }
  let(:custom_port) { 8080 }
  let(:incoming_api_projects_url) { "#{Gitlab.config.gitlab.url}:#{custom_port}/api/v4/projects" }

  before do
    stub_config_setting(port: custom_port)
  end

  describe '.paginate' do
    let(:base_query) { { per_page: 2 } }
    let(:query) { base_query }

    before do
      allow(request_context).to receive(:params).and_return(query)
      allow(request_context).to receive(:header)
    end

    shared_examples_for 'offset pagination' do
      let(:paginated_array) { double 'paginated array' }
      let(:branches) { [] }

      it 'uses offset pagination' do
        expect(finder).to receive(:execute).and_return(branches)
        expect(Kaminari).to receive(:paginate_array).with(branches).and_return(paginated_array)
        expect_next_instance_of(Gitlab::Pagination::OffsetPagination) do |offset_pagination|
          expect(offset_pagination).to receive(:paginate).with(paginated_array)
        end

        pager.paginate(finder)
      end
    end

    context 'with branch_list_keyset_pagination feature off' do
      before do
        stub_feature_flags(branch_list_keyset_pagination: false)
      end

      context 'without keyset pagination option' do
        it_behaves_like 'offset pagination'
      end

      context 'with keyset pagination option' do
        let(:query) { base_query.merge(pagination: 'keyset') }

        it_behaves_like 'offset pagination'
      end
    end

    context 'with branch_list_keyset_pagination feature on' do
      let(:fake_request) { double(url: "#{incoming_api_projects_url}?#{query.to_query}") }
      let(:branch1) { double 'branch', name: 'branch1' }
      let(:branch2) { double 'branch', name: 'branch2' }
      let(:branch3) { double 'branch', name: 'branch3' }

      before do
        stub_feature_flags(branch_list_keyset_pagination: project)
      end

      context 'without keyset pagination option' do
        context 'when first page is requested' do
          let(:branches) { [branch1, branch2, branch3] }

          before do
            allow(BranchesFinder).to receive(:===).with(finder).and_return(true)
            allow(finder).to receive(:total).and_return(branches.size)
          end

          it 'keyset pagination is used with offset headers' do
            allow(request_context).to receive(:request).and_return(fake_request)
            allow(project.repository).to receive(:branch_count).and_return(branches.size)

            expect(finder).to receive(:execute).and_return(branches)
            expect(request_context).to receive(:header).with('X-Per-Page', '2')
            expect(request_context).to receive(:header).with('X-Page', '1')
            expect(request_context).to receive(:header).with('X-Next-Page', '2')
            expect(request_context).to receive(:header).with('X-Prev-Page', '')
            expect(request_context).to receive(:header).with('Link', kind_of(String))
            expect(request_context).to receive(:header).with('X-Total', '3')
            expect(request_context).to receive(:header).with('X-Total-Pages', '2')

            pager.paginate(finder)
          end

          context 'when second page does not exist' do
            let(:base_query) { { per_page: 3 } }

            it 'does not set an invalid X-Next-Page header' do
              allow(request_context).to receive(:request).and_return(fake_request)
              allow(project.repository).to receive(:branch_count).and_return(branches.size)

              expect(finder).to receive(:execute).and_return(branches)
              expect(request_context).to receive(:header).with('X-Per-Page', '3')
              expect(request_context).to receive(:header).with('X-Page', '1')
              expect(request_context).to receive(:header).with('X-Next-Page', '')
              expect(request_context).to receive(:header).with('X-Prev-Page', '')
              expect(request_context).to receive(:header).with('Link', kind_of(String))
              expect(request_context).to receive(:header).with('X-Total', '3')
              expect(request_context).to receive(:header).with('X-Total-Pages', '1')

              pager.paginate(finder)
            end
          end
        end

        context 'when second page is requested' do
          let(:base_query) { { per_page: 2, page: 2 } }

          it_behaves_like 'offset pagination'
        end
      end

      context 'with keyset pagination option' do
        let(:query) { base_query.merge(pagination: 'keyset') }

        before do
          allow(request_context).to receive(:request).and_return(fake_request)
          allow(BranchesFinder).to receive(:===).with(finder).and_return(true)
          expect(finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)
          allow(finder).to receive(:next_cursor)
        end

        context 'when next page could be available' do
          let(:branches) { [branch1, branch2] }
          let(:next_cursor) { branch2.name }
          let(:expected_next_page_link) { %(<#{incoming_api_projects_url}?#{query.merge(page_token: next_cursor).to_query}>; rel="next") }

          before do
            allow(finder).to receive(:next_cursor).and_return(next_cursor)
          end

          it 'uses keyset pagination and adds link headers' do
            expect(request_context).to receive(:header).with('Link', expected_next_page_link)

            pager.paginate(finder)
          end
        end

        context 'when the current page is the last page' do
          let(:branches) { [branch1] }

          it 'uses keyset pagination without link headers' do
            expect(request_context).not_to receive(:header).with('Link', anything)

            pager.paginate(finder)
          end
        end

        context 'when the current page includes all requested elements and cursor is empty' do
          let(:base_query) { { per_page: 2 } }
          let(:branches) { [branch1, branch2] }
          let(:next_cursor) { '' }

          it 'uses keyset pagination without link headers' do
            expect(request_context).not_to receive(:header).with('Link', anything)

            pager.paginate(finder)
          end
        end
      end
    end

    context 'with bounded tag offset pagination' do
      let(:finder) { TagsFinder.new(project.repository, query.merge(bounded_tag_offset: true)) }
      let(:query) { { page: 2, per_page: 2 } }

      before do
        allow(request_context).to receive(:request)
          .and_return(double(url: "#{incoming_api_projects_url}?#{query.to_query}"))
        allow(finder).to receive(:total).and_return(7)
      end

      it 'returns the finder page without slicing it again and includes repository totals', :aggregate_failures do
        expect(finder).to receive(:execute).with(no_args).and_return([3, 4])
        expect(request_context).to receive(:header).with('X-Total', '7')
        expect(request_context).to receive(:header).with('X-Next-Page', '3')

        expect(pager.paginate(finder)).to eq([3, 4])
      end

      context 'when the finder uses different pagination values from the request' do
        let(:finder) { TagsFinder.new(project.repository, page: 3, per_page: 1, bounded_tag_offset: true) }

        it 'builds headers using the finder page and page size', :aggregate_failures do
          expect(finder).to receive(:execute).with(no_args).and_return([3])
          expect(request_context).to receive(:header).with('X-Page', '3')
          expect(request_context).to receive(:header).with('X-Per-Page', '1')
          expect(request_context).to receive(:header).with('X-Total-Pages', '7')
          expect(request_context).to receive(:header).with('X-Next-Page', '4')

          expect(pager.paginate(finder)).to eq([3])
        end
      end

      context 'without the opt-in' do
        let(:finder) { TagsFinder.new(project.repository, query) }

        it 'keeps the full-fetch path' do
          expect(finder).to receive(:execute).with(no_args).and_return([1, 2, 3, 4, 5])
          expect(finder).not_to receive(:total)

          expect(pager.paginate(finder)).to eq([3, 4])
        end
      end

      context 'with a stale repository count' do
        before do
          allow(finder).to receive(:total).and_return(1)
        end

        it 'preserves returned tags independently of header totals', :aggregate_failures do
          expect(finder).to receive(:execute).with(no_args).and_return([3, 4])
          expect(request_context).to receive(:header).with('X-Total', '1')
          expect(request_context).to receive(:header).with('X-Next-Page', '')

          expect(pager.paginate(finder)).to eq([3, 4])
        end
      end

      context 'when the count reaches the header threshold' do
        before do
          stub_const('Kaminari::ActiveRecordRelationMethods::MAX_COUNT_LIMIT', 7)
        end

        it 'omits totals and the last link without losing the next page', :aggregate_failures do
          expect(finder).to receive(:execute).with(no_args).and_return([3, 4])
          expect(request_context).not_to receive(:header).with('X-Total', anything)
          expect(request_context).not_to receive(:header).with('X-Total-Pages', anything)
          expect(request_context).to receive(:header).with('X-Next-Page', '3')
          expect(request_context).to receive(:header).with('Link', anything) do |_key, link|
            expect(link).not_to include('rel="last"')
          end

          expect(pager.paginate(finder)).to eq([3, 4])
        end
      end

      context 'on page one with an oversized per_page' do
        let(:query) { { page: 1, per_page: 200 } }

        it 'normalizes retrieval while preserving the existing first-page headers', :aggregate_failures do
          expect(finder).to receive(:execute).with(gitaly_pagination: true).and_return([1, 2])
          expect(request_context).to receive(:header).with('X-Per-Page', '200')

          expect(pager.paginate(finder)).to eq([1, 2])
        end
      end

      context 'on a later page with an oversized per_page' do
        let(:query) { { page: 2, per_page: 200 } }

        it 'preserves the finder page and uses the normalized size for navigation', :aggregate_failures do
          allow(finder).to receive(:total).and_return(250)
          expect(finder).to receive(:execute).and_return((101..200).to_a)
          expect(request_context).to receive(:header).with('X-Per-Page', '100')
          expect(request_context).to receive(:header).with('X-Total-Pages', '3')
          expect(request_context).to receive(:header).with('X-Next-Page', '3')

          expect(pager.paginate(finder)).to eq((101..200).to_a)
        end
      end

      context 'with a nonpositive page and a cursor' do
        let(:query) { { page: 0, page_token: 'v1', per_page: 2 } }

        it 'retains the legacy normalized offset page without honoring the cursor', :aggregate_failures do
          expect(finder).to receive(:execute).with(no_args).and_return([1, 2])
          expect(request_context).to receive(:header).with('X-Page', '1')

          expect(pager.paginate(finder)).to eq([1, 2])
        end
      end

      context 'when the repository has no tags' do
        before do
          allow(finder).to receive(:total).and_return(0)
        end

        it 'keeps the later-page empty total-page convention', :aggregate_failures do
          expect(finder).to receive(:execute).with(no_args).and_return([])
          expect(request_context).to receive(:header).with('X-Total-Pages', '1')

          expect(pager.paginate(finder)).to eq([])
        end

        context 'on the first page' do
          let(:query) { { page: 1, per_page: 2 } }

          it 'keeps the first-page empty total-page convention', :aggregate_failures do
            expect(finder).to receive(:execute).with(gitaly_pagination: true).and_return([])
            expect(request_context).to receive(:header).with('X-Total-Pages', '0')

            expect(pager.paginate(finder)).to eq([])
          end
        end
      end

      context 'with keyset pagination' do
        let(:query) { { pagination: 'keyset', page: 2, per_page: 2 } }

        it 'keeps the existing keyset path' do
          expect(finder).to receive(:execute).with(gitaly_pagination: true).and_return([])
          expect(finder).not_to receive(:total)

          expect(pager.paginate(finder)).to eq([])
        end
      end

      context 'with search' do
        let(:query) { { search: 'v1', page: 2, per_page: 2 } }

        it 'keeps the full-fetch path and filtered count' do
          expect(finder).to receive(:execute).with(no_args).and_return([1, 2, 3])
          expect(finder).not_to receive(:total)

          expect(pager.paginate(finder)).to eq([3])
        end
      end

      context 'with another finder' do
        let(:finder) { instance_double(BranchesFinder) }

        it 'does not pass tag-specific options' do
          expect(finder).to receive(:execute).with(no_args).and_return([1, 2, 3])

          expect(pager.paginate(finder)).to eq([3])
        end
      end
    end

    context 'with Gitlab::Git::Finders::BranchesFinder' do
      let(:git_finder) { double("git branches finder") }
      let(:fake_request) { double(url: "#{incoming_api_projects_url}?#{query.to_query}") }
      let(:branch1) { double 'branch', name: 'branch1' }
      let(:branch2) { double 'branch', name: 'branch2' }
      let(:branch3) { double 'branch', name: 'branch3' }

      before do
        allow(Gitlab::Git::Finders::BranchesFinder).to receive(:===).with(git_finder).and_return(true)
      end

      context 'with keyset pagination option' do
        let(:query) { base_query.merge(pagination: 'keyset') }

        before do
          allow(request_context).to receive(:request).and_return(fake_request)
          allow(git_finder).to receive(:next_cursor)
        end

        context 'when next page could be available' do
          let(:branches) { [branch1, branch2] }
          let(:next_cursor) { branch2.name }
          let(:expected_next_page_link) { %(<#{incoming_api_projects_url}?#{query.merge(page_token: next_cursor).to_query}>; rel="next") }

          before do
            allow(git_finder).to receive(:next_cursor).and_return(next_cursor)
          end

          it 'calls execute with gitaly_pagination: true and adds link headers' do
            expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)
            expect(request_context).to receive(:header).with('Link', expected_next_page_link)

            pager.paginate(git_finder)
          end
        end

        context 'when the current page is the last page' do
          let(:branches) { [branch1] }

          it 'calls execute with gitaly_pagination: true and does not add link headers' do
            expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)
            expect(request_context).not_to receive(:header).with('Link', anything)

            pager.paginate(git_finder)
          end
        end
      end

      context 'without keyset pagination option' do
        context 'when first page is requested' do
          let(:branches) { [branch1, branch2, branch3] }

          it 'calls execute with gitaly_pagination: true and uses offset headers' do
            allow(request_context).to receive(:request).and_return(fake_request)
            allow(git_finder).to receive(:total).and_return(branches.size)

            expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)
            expect(request_context).to receive(:header).with('X-Per-Page', '2')
            expect(request_context).to receive(:header).with('X-Page', '1')
            expect(request_context).to receive(:header).with('X-Next-Page', '2')
            expect(request_context).to receive(:header).with('X-Prev-Page', '')
            expect(request_context).to receive(:header).with('Link', kind_of(String))
            expect(request_context).to receive(:header).with('X-Total', '3')
            expect(request_context).to receive(:header).with('X-Total-Pages', '2')

            pager.paginate(git_finder)
          end
        end

        context 'when second page is requested' do
          let(:base_query) { { per_page: 2, page: 2 } }
          let(:branches) { [branch3] }

          before do
            allow(request_context).to receive(:request).and_return(fake_request)
            allow(git_finder).to receive(:total).and_return(5)
          end

          it 'returns finder results directly and sets correct pagination headers' do
            expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)

            result = pager.paginate(git_finder)

            expect(result).to eq([branch3])
            expect(request_context).to have_received(:header).with('X-Total', '5')
            expect(request_context).to have_received(:header).with('X-Total-Pages', '3')
            expect(request_context).to have_received(:header).with('X-Page', '2')
            expect(request_context).to have_received(:header).with('X-Prev-Page', '1')
            expect(request_context).to have_received(:header).with('X-Next-Page', '3')
          end
        end

        context 'when last page is requested' do
          let(:base_query) { { per_page: 2, page: 3 } }
          let(:branch5) { double 'branch', name: 'branch5' }
          let(:branches) { [branch5] }

          before do
            allow(request_context).to receive(:request).and_return(fake_request)
            allow(git_finder).to receive(:total).and_return(5)
          end

          it 'returns finder results directly and sets correct headers with no next page' do
            expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)

            result = pager.paginate(git_finder)

            expect(result).to eq([branch5])
            expect(request_context).to have_received(:header).with('X-Total', '5')
            expect(request_context).to have_received(:header).with('X-Total-Pages', '3')
            expect(request_context).to have_received(:header).with('X-Page', '3')
            expect(request_context).to have_received(:header).with('X-Prev-Page', '2')
            expect(request_context).to have_received(:header).with('X-Next-Page', '')
          end
        end

        context 'when search parameter is present' do
          context 'when first page is requested and next cursor exists' do
            let(:query) { { per_page: 2, search: 'feature' } }
            let(:branches) { [branch1, branch2] }

            before do
              allow(request_context).to receive(:request).and_return(fake_request)
              allow(git_finder).to receive_messages(next_cursor: 'some_cursor', total: nil)
            end

            it 'excludes X-Total and X-Total-Pages headers and uses next_cursor for next page', :aggregate_failures do
              expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)

              pager.paginate(git_finder)

              expect(request_context).to have_received(:header).with('X-Per-Page', '2')
              expect(request_context).to have_received(:header).with('X-Page', '1')
              expect(request_context).to have_received(:header).with('X-Next-Page', '2')
              expect(request_context).to have_received(:header).with('X-Prev-Page', '')
              expect(request_context).to have_received(:header).with('Link', kind_of(String))
              expect(request_context).not_to have_received(:header).with('X-Total', anything)
              expect(request_context).not_to have_received(:header).with('X-Total-Pages', anything)
            end
          end

          context 'when search returns no more results (no next cursor)' do
            let(:query) { { per_page: 2, search: 'feature' } }
            let(:branches) { [branch1] }

            before do
              allow(request_context).to receive(:request).and_return(fake_request)
              allow(git_finder).to receive_messages(next_cursor: nil, total: nil)
            end

            it 'does not set X-Next-Page and excludes total headers', :aggregate_failures do
              expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)

              pager.paginate(git_finder)

              expect(request_context).to have_received(:header).with('X-Next-Page', '')
              expect(request_context).not_to have_received(:header).with('X-Total', anything)
              expect(request_context).not_to have_received(:header).with('X-Total-Pages', anything)
            end
          end

          context 'when page 2 is requested with search' do
            let(:query) { { per_page: 2, page: 2, search: 'feature' } }
            let(:branches) { [branch3] }

            before do
              allow(request_context).to receive(:request).and_return(fake_request)
              allow(git_finder).to receive_messages(next_cursor: nil, total: nil)
            end

            it 'sets correct page headers without totals', :aggregate_failures do
              expect(git_finder).to receive(:execute).with(gitaly_pagination: true).and_return(branches)

              pager.paginate(git_finder)

              expect(request_context).to have_received(:header).with('X-Page', '2')
              expect(request_context).to have_received(:header).with('X-Prev-Page', '1')
              expect(request_context).to have_received(:header).with('X-Next-Page', '')
              expect(request_context).not_to have_received(:header).with('X-Total', anything)
              expect(request_context).not_to have_received(:header).with('X-Total-Pages', anything)
            end
          end
        end
      end
    end

    context 'with ::Repositories::CommitsFinder' do
      let(:commit1) { double 'commit', id: 'commit1' }
      let(:commit2) { double 'commit', id: 'commit2' }

      before do
        allow(::Repositories::CommitsFinder).to receive(:===).with(finder).and_return(true)
      end

      shared_examples 'falls back to offset pagination without calling total' do
        it 'uses offset pagination and does not call total', :aggregate_failures do
          expect(finder).not_to receive(:total)
          expect(finder).to receive(:execute).and_return([commit1])
          expect(Kaminari).to receive(:paginate_array).with([commit1]).and_return(double('paginated array'))
          expect_next_instance_of(Gitlab::Pagination::OffsetPagination) do |offset_pagination|
            expect(offset_pagination).to receive(:paginate)
          end

          pager.paginate(finder)
        end
      end

      context 'with commits_keyset_pagination feature on' do
        before do
          stub_feature_flags(commits_keyset_pagination: project)
        end

        context 'with keyset pagination option' do
          let(:fake_request) { double(url: "#{incoming_api_projects_url}?#{query.to_query}") }
          let(:query) { base_query.merge(pagination: 'keyset') }

          before do
            allow(request_context).to receive(:request).and_return(fake_request)
            allow(finder).to receive(:next_cursor)
          end

          context 'when next page could be available' do
            let(:next_cursor) { commit2.id }
            let(:expected_next_page_link) { %(<#{incoming_api_projects_url}?#{query.merge(page_token: next_cursor).to_query}>; rel="next") }

            before do
              allow(finder).to receive(:next_cursor).and_return(next_cursor)
            end

            it 'calls execute with gitaly_pagination: true and adds link headers', :aggregate_failures do
              commits = [commit1, commit2]

              expect(finder).to receive(:execute).with(gitaly_pagination: true).and_return(commits)
              expect(request_context).to receive(:header).with('Link', expected_next_page_link)

              pager.paginate(finder)
            end
          end

          context 'when the current page is the last page' do
            it 'calls execute with gitaly_pagination: true and does not add link headers', :aggregate_failures do
              commits = [commit1]

              expect(finder).to receive(:execute).with(gitaly_pagination: true).and_return(commits)
              expect(request_context).not_to receive(:header).with('Link', anything)

              pager.paginate(finder)
            end
          end

          context 'when the page is full but the cursor is nil' do
            it 'calls execute with gitaly_pagination: true and does not add link headers', :aggregate_failures do
              commits = [commit1, commit2]

              expect(finder).to receive(:execute).with(gitaly_pagination: true).and_return(commits)
              expect(request_context).not_to receive(:header).with('Link', anything)

              pager.paginate(finder)
            end
          end
        end

        context 'without keyset pagination option' do
          it_behaves_like 'falls back to offset pagination without calling total'
        end
      end

      context 'with commits_keyset_pagination feature off' do
        before do
          stub_feature_flags(commits_keyset_pagination: false)
        end

        context 'with keyset pagination option' do
          let(:query) { base_query.merge(pagination: 'keyset') }

          it_behaves_like 'falls back to offset pagination without calling total'
        end
      end
    end

    context "with 'none' pagination option" do
      let(:expected_result) { double(:result) }
      let(:query) { { pagination: 'none' } }

      context "with a finder that is not a TreeFinder" do
        it_behaves_like 'offset pagination'
      end

      context "with a finder that is a TreeFinder" do
        before do
          allow(finder).to receive(:is_a?).with(::Repositories::TreeFinder).and_return(true)
        end

        it "doesn't uses offset pagination" do
          expect(finder).to receive(:execute).with(gitaly_pagination: false).and_return(expected_result)
          expect(Kaminari).not_to receive(:paginate_array)
          expect(Gitlab::Pagination::OffsetPagination).not_to receive(:new)

          actual_result = pager.paginate(finder)
          expect(actual_result).to eq(expected_result)
        end
      end
    end
  end
end
