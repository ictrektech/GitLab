# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::ValueObject, feature_category: :artifact_registry do
  let(:value_object_class) do
    Class.new(described_class) do
      expose_attribute :id, :name
    end
  end

  describe '.expose_attribute' do
    subject(:value_object) { value_object_class.new('id' => 'abc', 'name' => 'widget') }

    it 'defines a reader per declared key that reads the parsed attributes', :aggregate_failures do
      expect(value_object.id).to eq('abc')
      expect(value_object.name).to eq('widget')
    end

    it 'reads nil for a declared key absent from the body' do
      expect(value_object_class.new('id' => 'abc').name).to be_nil
    end

    it "adds a subclass's readers to the subclass only", :aggregate_failures do
      child_class = Class.new(value_object_class) { expose_attribute :extra }

      expect(child_class.new('id' => 'abc', 'extra' => 1)).to have_attributes(id: 'abc', extra: 1)
      expect(value_object_class.new('extra' => 1)).not_to respond_to(:extra)
    end

    # GraphQL resolves Repository#format publicly.
    it 'keeps a declared reader public where Kernel defines a private method of that name' do
      value_object = Class.new(described_class) { expose_attribute :format }.new('format' => 'maven')

      expect(value_object.format).to eq('maven')
    end

    it 'is private, so a caller cannot add readers at runtime' do
      expect { value_object_class.expose_attribute(:other) }.to raise_error(NoMethodError)
    end
  end

  describe '#initialize' do
    it 'treats nil attributes as an empty resource rather than raising', :aggregate_failures do
      value_object = value_object_class.new(nil)

      expect(value_object.id).to be_nil
      expect(value_object.name).to be_nil
    end

    it 'defaults to an empty resource when constructed with no argument' do
      expect(value_object_class.new.id).to be_nil
    end
  end
end
