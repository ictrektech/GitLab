# frozen_string_literal: true

require_relative '../test_helper'
require 'tempfile'
require 'timeout'

describe IpynbDiff::InterruptibleTextDiff do
  let(:from) { IpynbDiff::Transformer.new(include_frontmatter: false).transform(FROM_IPYNB).as_text }
  let(:to) { IpynbDiff::Transformer.new(include_frontmatter: false).transform(TO_IPYNB).as_text }

  # The header lines name the temporary files, which differ on every run.
  def without_header(text)
    text.lines.reject { |line| line.start_with?('--- ', '+++ ') }.join
  end

  describe '.new' do
    using RSpec::Parameterized::TableSyntax

    where(:options, :message) do
      { source: 'files' }         | 'Only the strings source is supported'
      { allow_empty_diff: false } | 'Empty diffs must be allowed'
    end

    with_them do
      it 'raises for options it does not support' do
        expect { described_class.new(from, to, **options) }.to raise_error(ArgumentError, message)
      end
    end
  end

  describe '#to_s' do
    using RSpec::Parameterized::TableSyntax

    where(:include_diff_info) { [true, false] }

    with_them do
      it 'returns the same text as Diffy::Diff' do
        expected = Diffy::Diff.new(from, to, include_diff_info: include_diff_info).to_s(:text)
        text = described_class.new(from, to, include_diff_info: include_diff_info).to_s(:text)

        expect(text).to include('@@') if include_diff_info
        expect(without_header(text)).to eq(without_header(expected))
        expect(text.encoding).to eq(expected.encoding)
      end
    end

    context 'when a text is not valid UTF-8' do
      let(:from) { "caf\xE9\n" }
      let(:to) { "cafe\n" }

      it 'returns binary text, as Diffy::Diff does' do
        expected = Diffy::Diff.new(from, to, include_diff_info: true).to_s(:text)
        text = described_class.new(from, to, include_diff_info: true).to_s(:text)

        expect(text.encoding).to eq(Encoding::ASCII_8BIT)
        expect(without_header(text)).to eq(without_header(expected))
      end
    end

    context 'when both texts are equal' do
      it 'returns an empty text' do
        expect(described_class.new(from, from).to_s(:text)).to eq('')
      end
    end
  end

  describe '#diff' do
    let(:text_diff) { described_class.new(from, to) }
    let(:tempfile_paths) { [] }

    before do
      allow(Tempfile).to receive(:new).and_wrap_original do |method, *args|
        method.call(*args).tap { |file| tempfile_paths << file.path if args.first == 'diffy' }
      end
    end

    it 'removes its temporary files' do
      text_diff.diff

      expect(tempfile_paths.size).to eq(2)
      expect(tempfile_paths).to all(satisfy { |path| !File.exist?(path) })
    end

    context 'when the diff process fails' do
      using RSpec::Parameterized::TableSyntax

      where(:script) do
        [
          "echo partial; exit 2",
          "echo partial; kill -9 $$"
        ]
      end

      with_them do
        let(:failing_diff) do
          Tempfile.new('failing_diff').tap do |file|
            file.write("#!/bin/sh\n#{script}\n")
            file.close
            File.chmod(0o755, file.path)
          end
        end

        after do
          failing_diff.unlink
        end

        it 'raises instead of returning the partial output' do
          allow(text_diff).to receive(:diff_bin).and_return(failing_diff.path)

          expect { text_diff.diff }.to raise_error(IpynbDiff::DiffError, /diff failed/)
        end
      end
    end

    context 'when the calling thread is interrupted' do
      let(:slow_diff) do
        Tempfile.new('slow_diff').tap do |file|
          file.write("#!/bin/sh\nexec sleep 10\n")
          file.close
          File.chmod(0o755, file.path)
        end
      end

      let(:pids) { [] }

      before do
        allow(text_diff).to receive(:diff_bin).and_return(slow_diff.path)
        allow(Process).to receive(:spawn).and_wrap_original do |method, *args, **kwargs|
          method.call(*args, **kwargs).tap { |pid| pids << pid }
        end
      end

      after do
        slow_diff.unlink
      end

      context 'when diff_bin is a wrapper that starts another process' do
        let(:slow_diff) do
          Tempfile.new('slow_diff').tap do |file|
            file.write("#!/bin/sh\nsleep 10 &\necho $! > \"$0.child\"\nexec sleep 10\n")
            file.close
            File.chmod(0o755, file.path)
          end
        end

        after do
          FileUtils.rm_f("#{slow_diff.path}.child")
        end

        it 'kills the other process too' do
          child_pid_path = "#{slow_diff.path}.child"

          expect { Timeout.timeout(0.5) { text_diff.diff } }.to raise_error(Timeout::Error)

          child_pid = Integer(File.read(child_pid_path))
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2

          # The killed child is reaped by init, so poll until it is gone.
          loop do
            Process.kill(0, child_pid)
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

            sleep 0.05
          rescue Errno::ESRCH
            break
          end

          expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
        end
      end

      it 'kills and reaps the diff process' do
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect { Timeout.timeout(0.2) { text_diff.diff } }.to raise_error(Timeout::Error)

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).to be < 2
        expect(pids.size).to eq(1)
        expect { Process.kill(0, pids.first) }.to raise_error(Errno::ESRCH)
        expect(tempfile_paths).to all(satisfy { |path| !File.exist?(path) })
      end
    end
  end
end
