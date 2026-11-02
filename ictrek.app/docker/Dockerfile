# syntax=docker/dockerfile:1
ARG BASE_IMAGE=gitlab/gitlab-ee@sha256:fb51b202d69ffb97cb2aeaf3558cb653147d0c7014fe1855b752cb5675bd4a6e
FROM ${BASE_IMAGE}
ARG GITLAB_VERSION
ARG SOURCE_COMMIT
ARG TARGETARCH
LABEL org.opencontainers.image.source="https://github.com/ictrektech/GitLab" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.version="${GITLAB_VERSION}"
COPY overlay/ /opt/gitlab/embedded/service/gitlab-rails/
COPY vos-init /assets/vos-init
COPY vos-config.rb /assets/vos-config.rb
COPY prepare-pgv.rb /assets/prepare-pgv.rb
RUN test "$(cat /opt/gitlab/embedded/service/gitlab-rails/VERSION)" = "$GITLAB_VERSION" \
    && test -f /opt/gitlab/embedded/service/gitlab-rails/lib/gitlab/application_rate_limiter/labkit_adapter/supported_rate_limits.rb \
    && case "$TARGETARCH" in amd64|arm64) true ;; *) exit 1 ;; esac \
    && chmod 755 /assets/vos-init
CMD ["/assets/vos-init"]
