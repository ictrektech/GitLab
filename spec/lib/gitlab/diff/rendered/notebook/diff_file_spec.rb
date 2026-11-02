# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Diff::Rendered::Notebook::DiffFile, feature_category: :mlops do
  include RepoHelpers

  let_it_be(:project) { create(:project, :repository) }

  let(:commit) { project.commit("5d6ed1503801ca9dc28e95eeb85a7cf863527aee") }
  let(:diffs) { commit.raw_diffs.to_a }
  let(:diff) { diffs.first }
  let(:source) { Gitlab::Diff::File.new(diff, diff_refs: commit.diff_refs, repository: project.repository) }
  let(:nb_file) { described_class.new(source) }

  describe '#old_blob and #new_blob' do
    context 'when file is changed' do
      it 'transforms the old blob' do
        expect(nb_file.old_blob.data).to include('%%')
      end

      it 'transforms the new blob' do
        expect(nb_file.new_blob.data).to include('%%')
      end
    end

    context 'when file is added' do
      let(:diff) { diffs[1] }

      it 'old_blob is empty' do
        expect(nb_file.old_blob).to be_nil
      end

      it 'new_blob is transformed' do
        expect(nb_file.new_blob.data).to include('%%')
      end
    end

    context 'when file is removed' do
      let(:diff) { diffs[2] }

      it 'old_blob is transformed' do
        expect(nb_file.old_blob.data).to include('%%')
      end

      it 'new_blob is empty' do
        expect(nb_file.new_blob).to be_nil
      end
    end
  end

  describe '#diff' do
    context 'for valid notebooks' do
      it 'returns the transformed diff' do
        expect(nb_file.diff.diff).to include('%%')
      end
    end

    context 'for invalid notebooks' do
      let(:commit) { project.commit("6d85bb693dddaee631ec0c2f697c52c62b93f6d3") }
      let(:diff) { diffs[1] }

      it 'returns nil' do
        expect(nb_file.diff).to be_nil
      end
    end

    context 'when IpynbDiff returns no diff' do
      before do
        allow(IpynbDiff).to receive(:diff).and_return(nil)
        allow(Gitlab::AppLogger).to receive(:info).and_call_original
      end

      it 'returns nil, without logging a generated diff' do
        expect(nb_file.diff).to be_nil
        expect(Gitlab::AppLogger).not_to have_received(:info)
          .with({ message: described_class::LOG_IPYNBDIFF_GENERATED })
      end
    end

    context 'when the diff file has no repository' do
      before do
        allow(nb_file).to receive(:repository).and_return(nil)
      end

      it 'computes the text diff inside the timeout' do
        expect(IpynbDiff).to receive(:diff).with(anything, anything, hash_including(interruptible: true))
          .and_call_original

        expect(nb_file.diff.diff).to include('%%')
      end
    end

    context 'timeout' do
      it 'utilizes timeout for web' do
        expect(Timeout).to receive(:timeout).with(Gitlab::RenderTimeout::FOREGROUND).and_call_original

        nb_file.diff
      end

      it 'falls back to nil on timeout' do
        expect(Gitlab::ErrorTracking).to receive(:log_exception)
        expect(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        expect(nb_file.diff).to be_nil
      end

      it 'utilizes longer timeout for sidekiq' do
        allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)
        expect(Timeout).to receive(:timeout).with(described_class::RENDERED_TIMEOUT_BACKGROUND).and_call_original

        nb_file.diff
      end

      it 'counts a timeout in sidekiq as background' do
        counter = instance_double(Prometheus::Client::Counter, increment: nil)
        allow(Gitlab::Metrics).to receive(:counter).and_call_original
        allow(Gitlab::Metrics).to receive(:counter)
          .with(:ipynb_semantic_diff_timeouts_total, anything).and_return(counter)
        allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        expect(nb_file.diff).to be_nil
        expect(counter).to have_received(:increment).with(source: described_class::BACKGROUND_EXECUTION)
      end

      context 'when the text diff takes longer than the timeout' do
        let(:slow_diff) do
          Tempfile.new('slow_diff').tap do |file|
            file.write("#!/bin/sh\nexec sleep 30\n")
            file.close
            File.chmod(0o755, file.path)
          end
        end

        let(:pids) { [] }

        before do
          # Leaves time for the transform on slow runners, far below the 30 s of the diff process.
          stub_const('Gitlab::RenderTimeout::FOREGROUND', 3)

          allow_next_instance_of(IpynbDiff::InterruptibleTextDiff) do |text_diff|
            allow(text_diff).to receive(:diff_bin).and_return(slow_diff.path)
          end

          allow(Process).to receive(:spawn).and_wrap_original do |method, *args, **kwargs|
            method.call(*args, **kwargs).tap { |pid| pids << pid }
          end
        end

        after do
          slow_diff.unlink
        end

        context 'when stop_notebook_text_diff_at_timeout is disabled' do
          before do
            stub_feature_flags(stop_notebook_text_diff_at_timeout: false)
          end

          it 'computes the text diff with Diffy::Diff, without the slow diff process' do
            expect(IpynbDiff).to receive(:diff).with(anything, anything, hash_including(interruptible: false))
              .and_call_original

            expect(nb_file.diff.diff).to include('%%')
            expect(pids).to be_empty
          end
        end

        it 'stops the diff process at the timeout' do
          expect(Gitlab::ErrorTracking).to receive(:log_exception).with(an_instance_of(Timeout::Error))

          started_at = Gitlab::Metrics::System.monotonic_time

          expect(nb_file.diff).to be_nil
          expect(Gitlab::Metrics::System.monotonic_time - started_at).to be < 10
          expect(pids.size).to eq(1)
          expect { Process.kill(0, pids.first) }.to raise_error(Errno::ESRCH)
        end
      end
    end
  end

  describe 'rendered diff cache', :use_clean_rails_redis_caching do
    let(:other_nb_file) do
      described_class.new(
        Gitlab::Diff::File.new(diff, diff_refs: commit.diff_refs, repository: project.repository)
      )
    end

    def rendered_output(file)
      lines = file.highlighted_diff_lines.map(&:to_hash)

      [file.diff.diff, file.diff.diff.encoding, file.old_blob.data, file.new_blob.data, lines]
    end

    before do
      allow(IpynbDiff).to receive(:diff).and_call_original
    end

    it 'renders the same blobs once' do
      rendered_output(nb_file)
      rendered_output(other_nb_file)

      expect(IpynbDiff).to have_received(:diff).once
    end

    it 'returns the same output as without the cache' do
      rendered = rendered_output(nb_file)
      cached = rendered_output(other_nb_file)

      stub_feature_flags(cache_notebook_diffs: false)
      uncached = rendered_output(described_class.new(source))

      expect(rendered).to eq(uncached)
      expect(cached).to eq(uncached)
    end

    context 'when the render times out' do
      before do
        allow(Gitlab::RenderTimeout).to receive(:timeout).and_raise(Timeout::Error)
      end

      it 'shows the raw diff, without rendering again while the marker lives' do
        expect(nb_file.rendered).to be_nil
        expect(other_nb_file.rendered).to be_nil

        expect(Gitlab::RenderTimeout).to have_received(:timeout).once
      end
    end

    context 'when the diff process fails' do
      let(:failing_diff) do
        Tempfile.new('failing_diff').tap do |file|
          file.write("#!/bin/sh\necho partial\nexit 2\n")
          file.close
          File.chmod(0o755, file.path)
        end
      end

      before do
        allow_next_instances_of(IpynbDiff::InterruptibleTextDiff, 2) do |text_diff|
          allow(text_diff).to receive(:diff_bin).and_return(failing_diff.path)
        end
      end

      after do
        failing_diff.unlink
      end

      it 'shows the raw diff, and does not cache the failure' do
        expect(Gitlab::ErrorTracking).to receive(:log_exception).with(an_instance_of(IpynbDiff::DiffError)).twice

        expect(nb_file.rendered).to be_nil
        expect(other_nb_file.rendered).to be_nil
        expect(IpynbDiff).to have_received(:diff).twice
      end
    end

    context 'when cache_notebook_diffs is disabled' do
      before do
        stub_feature_flags(cache_notebook_diffs: false)
      end

      it 'renders the notebooks on every call' do
        rendered_output(nb_file)
        rendered_output(other_nb_file)

        expect(IpynbDiff).to have_received(:diff).twice
      end
    end

    context 'when the diff file has no repository' do
      before do
        allow(nb_file).to receive(:repository).and_return(nil)
      end

      it 'does not use the cache' do
        expect(Gitlab::Diff::Rendered::Notebook::DiffCache).not_to receive(:new)

        expect(nb_file.diff.diff).to include('%%')
      end
    end

    context 'when the repository has no project' do
      before do
        allow(source.repository).to receive(:project).and_return(nil)
      end

      it 'does not use the cache' do
        expect(Gitlab::Diff::Rendered::Notebook::DiffCache).not_to receive(:new)

        expect(nb_file.diff.diff).to include('%%')
      end
    end
  end

  describe '#has_renderable?' do
    context 'notebook diff is empty' do
      let(:commit) { project.commit("a867a602d2220e5891b310c07d174fbe12122830") }

      it 'is false' do
        expect(nb_file.has_renderable?).to be_falsey
      end
    end

    context 'notebook is valid' do
      it 'is true' do
        expect(nb_file.has_renderable?).to be_truthy
      end
    end

    context 'when old blob file is truncated' do
      it 'is false' do
        allow(source.old_blob).to receive(:truncated?).and_return(true)

        expect(nb_file.has_renderable?).to be_falsey
      end
    end

    context 'when new blob file is truncated' do
      it 'is false' do
        allow(source.new_blob).to receive(:truncated?).and_return(true)

        expect(nb_file.has_renderable?).to be_falsey
      end
    end
  end

  describe '#highlighted_diff_lines?' do
    it 'does not have any match lines' do
      expect(nb_file.highlighted_diff_lines.all? { |line| line.type != 'match' }).to be_truthy
    end

    context 'when line transformed line is not part of the diff' do
      it 'line is not discussable' do
        expect(nb_file.highlighted_diff_lines[0].discussable?).to be_falsey
      end
    end

    context 'when line transformed line part of the diff' do
      it 'line is not discussable' do
        expect(nb_file.highlighted_diff_lines[12].discussable?).to be_truthy
      end
    end

    context 'assigns the correct position' do
      it 'computes the first line where the remove would appear' do
        expect(nb_file.highlighted_diff_lines[0].old_pos).to eq(3)
        expect(nb_file.highlighted_diff_lines[0].new_pos).to eq(3)

        expect(nb_file.highlighted_diff_lines[12].new_pos).to eq(15)
        expect(nb_file.highlighted_diff_lines[12].old_pos).to eq(18)
      end
    end

    context 'has image' do
      it 'replaces rich text with img to the embedded image' do
        expect(nb_file.highlighted_diff_lines[56].rich_text).to include('<img')
      end

      it 'adds image to src' do
        img = 'data:image/png;base64,some_image_here'
        allow(diff).to receive(:diff).and_return("@@ -1,76 +1,74 @@\n     ![](#{img})")

        expect(nb_file.highlighted_diff_lines[0].rich_text).to include("<img src=\"#{img}\"")
      end
    end

    context 'when embedded image has injected html' do
      let(:commit) { project.commit("4963fefc990451a8ad34289ce266b757456fc88c") }

      it 'prevents injected html to be rendered as html' do
        expect(nb_file.highlighted_diff_lines[43].rich_text).not_to include('<div>Hello')
      end

      it 'keeps the injected html as part of the string' do
        expect(nb_file.highlighted_diff_lines[43].rich_text).to end_with('/div&gt;">')
      end
    end
  end

  describe '#rendered' do
    context 'when notebook_diff is present' do
      it 'returns self' do
        expect(nb_file.rendered).to eq(nb_file)
      end
    end

    context 'when notebook_diff is nil' do
      it 'returns nil' do
        allow(nb_file).to receive(:notebook_diff).and_return(nil)

        expect(nb_file.rendered).to be_nil
      end
    end
  end

  describe '#rendered?' do
    it { expect(nb_file.rendered?).to be_truthy }
  end

  describe '#diff_lines_with_match_tail' do
    it 'returns highlighted lines by default' do
      expect(nb_file.diff_lines_with_match_tail).to eq(nb_file.highlighted_diff_lines)
    end

    context 'when highlighted_diff_lines is empty' do
      it 'returns an empty array' do
        allow(nb_file).to receive(:highlighted_diff_lines).and_return([])

        expect(nb_file.diff_lines_with_match_tail).to eq([])
      end
    end

    context 'when blob is nil' do
      it 'returns an empty array' do
        allow(nb_file).to receive(:blob).and_return(nil)

        expect(nb_file.diff_lines_with_match_tail).to eq([])
      end
    end

    context 'when there are highlighted diff lines and blob exists' do
      it 'returns the highlighted diff lines' do
        expect(nb_file.diff_lines_with_match_tail).to eq(nb_file.highlighted_diff_lines)
      end
    end
  end
end
