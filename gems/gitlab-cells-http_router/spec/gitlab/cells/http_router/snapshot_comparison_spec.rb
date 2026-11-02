# frozen_string_literal: true

RSpec.describe Gitlab::Cells::HttpRouter::SnapshotComparison do
  # A snapshot has to clear MIN_ROUTES to be accepted, so build the bulk of it
  # from filler and append the routes a given example actually cares about.
  def payload(*routes, filler: described_class::MIN_ROUTES, pretty: true)
    entries = Array.new(filler) { |i| { "template" => "/filler/#{i}", "example" => "/filler/#{i}" } }
    entries += routes.map { |route| route.is_a?(Hash) ? route : { "template" => route, "example" => route } }

    pretty ? "#{JSON.pretty_generate(entries)}\n" : JSON.generate(entries)
  end

  def compare(gitlab:, base:, router:)
    described_class.new(gitlab_payload: gitlab, base_payload: base, router_payload: router)
  end

  describe "#in_sync?" do
    it "is true when the router has every route the branch adds" do
      comparison = compare(gitlab: payload("/a", "/d"), base: payload("/a"), router: payload("/a", "/d"))

      expect(comparison).to be_in_sync
    end

    # The router snapshot carries the routes of every open merge request, so
    # two branches that each add a different route must both pass against it.
    it "is true for two branches that add different routes when the router has both" do
      router = payload("/a", "/d", "/e")

      expect(compare(gitlab: payload("/a", "/d"), base: payload("/a"), router: router)).to be_in_sync
      expect(compare(gitlab: payload("/a", "/e"), base: payload("/a"), router: router)).to be_in_sync
    end

    it "is false when the router does not have a route the branch adds" do
      comparison = compare(gitlab: payload("/a", "/d"), base: payload("/a"), router: payload("/a", "/e"))

      expect(comparison).not_to be_in_sync
      expect(comparison.missing).to eq(["/d"])
      expect(comparison.outdated).to be_empty
    end

    it "ignores a route the router does not have when the target branch already has it" do
      comparison = compare(gitlab: payload("/a", "/x"), base: payload("/a", "/x"), router: payload("/a"))

      expect(comparison).to be_in_sync
    end

    it "ignores a route the branch removes" do
      comparison = compare(gitlab: payload("/a"), base: payload("/a", "/d"), router: payload("/a", "/d"))

      expect(comparison).to be_in_sync
    end

    it "ignores formatting and key order" do
      gitlab = payload({ "template" => "/d", "example" => "/d", "acceptsFormat" => true }, pretty: true)
      router = payload({ "acceptsFormat" => true, "example" => "/d", "template" => "/d" }, pretty: false)

      expect(compare(gitlab: gitlab, base: payload, router: router)).to be_in_sync
    end
  end

  describe "#outdated" do
    let(:old_route) { { "template" => "/a", "example" => "/a" } }
    let(:new_route) { old_route.merge("acceptsFormat" => true) }

    it "lists a route whose fields the branch changes when the router has the old fields" do
      comparison = compare(gitlab: payload(new_route), base: payload(old_route), router: payload(old_route))

      expect(comparison).not_to be_in_sync
      expect(comparison.outdated).to eq(["/a"])
      expect(comparison.missing).to be_empty
    end

    it "lists a route the branch adds when the router has it with other fields" do
      comparison = compare(gitlab: payload(new_route), base: payload, router: payload(old_route))

      expect(comparison.outdated).to eq(["/a"])
      expect(comparison.missing).to be_empty
    end

    it "lists a route when the router has fields that match neither the base nor the branch" do
      other_route = old_route.merge("dottedExample" => "/a.b")

      comparison = compare(gitlab: payload(new_route), base: payload(old_route), router: payload(other_route))

      expect(comparison.outdated).to eq(["/a"])
    end

    it "is empty when the router has the new fields" do
      comparison = compare(gitlab: payload(new_route), base: payload(old_route), router: payload(new_route))

      expect(comparison).to be_in_sync
    end
  end

  describe "#missing" do
    it "sorts the templates" do
      comparison = compare(gitlab: payload("/z", "/a", "/m"), base: payload, router: payload)

      expect(comparison.missing).to eq(%w[/a /m /z])
    end
  end

  describe "invalid payloads" do
    it "rejects a non-JSON body, naming the side it came from" do
      expect { compare(gitlab: payload("/a"), base: payload, router: "<!DOCTYPE html>") }
        .to raise_error(described_class::InvalidSnapshotError, /HTTP Router snapshot is not valid JSON/)
    end

    it "rejects a JSON object" do
      expect { compare(gitlab: payload("/a"), base: payload, router: '{"routes":[]}') }
        .to raise_error(described_class::InvalidSnapshotError, /expected an array of routes/)
    end

    it "rejects a truncated array" do
      expect { compare(gitlab: payload("/a"), base: payload, router: payload(filler: 10)) }
        .to raise_error(described_class::InvalidSnapshotError, /holds only 10 routes/)
    end

    it "rejects an entry without a template" do
      routes = Array.new(described_class::MIN_ROUTES) { { "example" => "/x" } }

      expect { compare(gitlab: payload("/a"), base: payload, router: JSON.generate(routes)) }
        .to raise_error(described_class::InvalidSnapshotError, /entry without a template/)
    end

    it "rejects a duplicate template" do
      duplicated = payload({ "template" => "/a", "example" => "/a" }, { "template" => "/a", "example" => "/a.json" })

      expect { compare(gitlab: payload("/a"), base: payload, router: duplicated) }
        .to raise_error(described_class::InvalidSnapshotError, %r{HTTP Router snapshot has a duplicate template: /a})
    end

    it "names the GitLab side when that is the invalid one" do
      expect { compare(gitlab: "[]", base: payload, router: payload("/a")) }
        .to raise_error(described_class::InvalidSnapshotError, /GitLab snapshot holds only 0 routes/)
    end

    it "names the target branch side when that is the invalid one" do
      expect { compare(gitlab: payload("/a"), base: "<!DOCTYPE html>", router: payload("/a")) }
        .to raise_error(described_class::InvalidSnapshotError, /snapshot on the target branch is not valid JSON/)
    end

    it "exposes the side that failed, so a caller can tell a bad download from a bad local file" do
      expect { compare(gitlab: payload("/a"), base: payload, router: "<!DOCTYPE html>") }
        .to raise_error(described_class::InvalidSnapshotError) { |error| expect(error.source).to eq(:router) }

      expect { compare(gitlab: payload("/a"), base: "[]", router: payload("/a")) }
        .to raise_error(described_class::InvalidSnapshotError) { |error| expect(error.source).to eq(:base) }

      expect { compare(gitlab: "[]", base: payload, router: payload("/a")) }
        .to raise_error(described_class::InvalidSnapshotError) { |error| expect(error.source).to eq(:gitlab) }
    end
  end
end
