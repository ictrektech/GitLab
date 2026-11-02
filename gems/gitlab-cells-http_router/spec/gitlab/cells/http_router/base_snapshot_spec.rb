# frozen_string_literal: true

RSpec.describe Gitlab::Cells::HttpRouter::BaseSnapshot do
  describe ".url" do
    it "points at GitLab's snapshot via the Repository Files API on master" do
      expect(described_class.url).to eq(
        "https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab" \
          "/repository/files/config%2Frouting%2Fgitlab_routes.json/raw?ref=master"
      )
    end

    it "accepts another ref, project and API URL" do
      url = described_class.url(project: "gitlab-org/security/gitlab", ref: "abc123", api_url: "https://example.com/api/v4")

      expect(url).to eq(
        "https://example.com/api/v4/projects/gitlab-org%2Fsecurity%2Fgitlab" \
          "/repository/files/config%2Frouting%2Fgitlab_routes.json/raw?ref=abc123"
      )
    end
  end

  describe ".url_from_env" do
    it "falls back to the defaults when nothing is set" do
      expect(described_class.url_from_env({})).to eq(described_class.url)
    end

    it "reads the merge request's target project, so the security mirror compares against itself" do
      url = described_class.url_from_env({ "CI_MERGE_REQUEST_PROJECT_PATH" => "gitlab-org/security/gitlab" })

      expect(url).to eq(described_class.url(project: "gitlab-org/security/gitlab"))
    end

    it "honours a CI_API_V4_URL override" do
      url = described_class.url_from_env({ "CI_API_V4_URL" => "https://example.com/api/v4" })

      expect(url).to eq(described_class.url(api_url: "https://example.com/api/v4"))
    end

    it "lets a full URL override bypass all other variables" do
      url = described_class.url_from_env(
        { "CELLS_ROUTES_BASE_URL" => "https://example.com/base.json", "CELLS_ROUTES_BASE_REF" => "ignored" }
      )

      expect(url).to eq("https://example.com/base.json")
    end
  end

  describe ".ref_from_env" do
    it "uses the target branch SHA in a merged results pipeline" do
      env = { "CI_MERGE_REQUEST_TARGET_BRANCH_SHA" => "target", "CI_MERGE_REQUEST_DIFF_BASE_SHA" => "merge-base" }

      expect(described_class.ref_from_env(env)).to eq("target")
    end

    it "uses the merge-base when the target branch SHA is empty" do
      env = { "CI_MERGE_REQUEST_TARGET_BRANCH_SHA" => "", "CI_MERGE_REQUEST_DIFF_BASE_SHA" => "merge-base" }

      expect(described_class.ref_from_env(env)).to eq("merge-base")
    end

    it "lets CELLS_ROUTES_BASE_REF override the pipeline variables" do
      env = { "CELLS_ROUTES_BASE_REF" => "my-ref", "CI_MERGE_REQUEST_TARGET_BRANCH_SHA" => "target" }

      expect(described_class.ref_from_env(env)).to eq("my-ref")
    end

    it "falls back to master outside a merge request pipeline" do
      expect(described_class.ref_from_env({})).to eq("master")
    end
  end
end
