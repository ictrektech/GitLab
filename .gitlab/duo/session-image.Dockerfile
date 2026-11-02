# Built by build-duo-session-image in .gitlab/ci/duo-session-image.gitlab-ci.yml.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG REPOSITORY_URL
ARG COMMIT_SHA

# The branch ref is required: a fetch only offers an alternate's refs as haves, so a
# repository without refs makes every session download the whole history again.
RUN git init --quiet --bare /opt/duo/ref.git \
  && git -C /opt/duo/ref.git fetch --quiet --no-tags "${REPOSITORY_URL}" "${COMMIT_SHA}:refs/heads/master"
