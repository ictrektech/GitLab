# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Banzai::Filter::TableOfContentsTagFilter do
  include FilterSpecHelper

  let(:headers) do
    '<h1><a class="anchor" href="#foo"></a>Foo</h1>' \
      '<h2><a class="anchor" href="#bar"></a>Bar</h2>' \
      '<h1><a class="anchor" href="#baz"></a>Baz</h1>'
  end

  it 'replaces a `[TOC]` paragraph with the list of headers' do
    doc = filter("<p>[TOC]</p>#{headers}")

    expect(doc.at_css('ul.section-nav').to_html).to eq_html(
      '<ul class="section-nav">' \
        '<li><a href="#foo">Foo</a><ul><li><a href="#bar">Bar</a></li></ul></li>' \
        '<li><a href="#baz">Baz</a></li>' \
        '</ul>'
    )
  end

  it 'nests the list by header level' do
    doc = filter(
      '<p>[TOC]</p>' \
        '<h1><a class="anchor" href="#h1"></a>Header 1</h1>' \
        '<h2><a class="anchor" href="#h1-1"></a>Header 1-1</h2>' \
        '<h3><a class="anchor" href="#h1-1-1"></a>Header 1-1-1</h3>' \
        '<h2><a class="anchor" href="#h1-2"></a>Header 1-2</h2>' \
        '<h1><a class="anchor" href="#h2"></a>Header 2</h1>' \
        '<h2><a class="anchor" href="#h2-1"></a>Header 2-1</h2>' \
        '<h2><a class="anchor" href="#h2-1b"></a>Header 2-1b</h2>'
    )

    expect(doc.at_css('ul.section-nav').to_html).to eq_html(
      '<ul class="section-nav">' \
        '<li><a href="#h1">Header 1</a><ul>' \
        '<li><a href="#h1-1">Header 1-1</a><ul><li><a href="#h1-1-1">Header 1-1-1</a></li></ul></li>' \
        '<li><a href="#h1-2">Header 1-2</a></li>' \
        '</ul></li>' \
        '<li><a href="#h2">Header 2</a><ul>' \
        '<li><a href="#h2-1">Header 2-1</a></li>' \
        '<li><a href="#h2-1b">Header 2-1b</a></li>' \
        '</ul></li>' \
        '</ul>'
    )
  end

  it 'keeps escaped header text escaped' do
    content = '&lt;img src="x" onerror="alert(42)"&gt;'
    doc = filter(%(<p>[TOC]</p><h1><a class="anchor" href="#x"></a>#{content}</h1>))

    expect(doc.at_css('ul.section-nav a').inner_html).to eq(content)
    expect(doc.css('img')).to be_empty
  end

  it 'replaces a Gollum `[[_TOC_]]` wikilink' do
    doc = filter(%(<p><a data-wikilink="true" href="_TOC_">_TOC_</a></p>#{headers}))

    expect(doc.at_css('ul.section-nav')).to be_present
  end

  it 'ignores the tag inside a sentence' do
    doc = filter("<p>see [TOC] here</p>#{headers}")

    expect(doc.at_css('ul.section-nav')).to be_nil
  end

  it 'leaves the document alone when header anchors are disabled' do
    doc = filter("<p>[TOC]</p>#{headers}", no_header_anchors: true)

    expect(doc.at_css('ul.section-nav')).to be_nil
  end

  it 'removes the tag when there are no headers' do
    expect(filter('<p>[TOC]</p>').to_html).to eq('')
  end

  it_behaves_like 'pipeline timing check'
end
