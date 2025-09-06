# Dockerfile - Debian-based self-hosted GitHub Actions runner
FROM debian:bookworm-slim

ARG RUNNER_OS=linux
ARG RUNNER_ARCH=x64
ARG RUNNER_VERSION=latest   # set a specific version at build time for reproducibility, e.g. 2.325.0
ENV RUNNER_ROOT=/home/runner

# install minimal tools (build steps run as root)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl jq git tar gzip procps wget gnupg2 dumb-init && \
    rm -rf /var/lib/apt/lists/*

# Download runner (latest by default) and extract
RUN set -eux; \
    if [ "$RUNNER_VERSION" = "latest" ]; then \
      TAG=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name); \
      VERSION=${TAG#v}; \
    else \
      VERSION="$RUNNER_VERSION"; TAG="v${RUNNER_VERSION}"; \
    fi; \
    echo "Using runner release: ${TAG:-v$VERSION}"; \
    curl -fsSL -o /tmp/actions-runner.tar.gz \
      "https://github.com/actions/runner/releases/download/${TAG:-v$VERSION}/actions-runner-${RUNNER_OS}-${RUNNER_ARCH}-${VERSION}.tar.gz"; \
    mkdir -p $RUNNER_ROOT && tar xzf /tmp/actions-runner.tar.gz -C $RUNNER_ROOT && rm /tmp/actions-runner.tar.gz

# Let the runner's helper install any system dependencies (script exists in the runner distribution)
RUN set -eux; cd $RUNNER_ROOT && ./bin/installdependencies.sh || true

# Create a non-root user
RUN useradd -m runner && chown -R runner:runner $RUNNER_ROOT

# Copy entrypoint (below) and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
WORKDIR $RUNNER_ROOT

ENTRYPOINT ["/entrypoint.sh"]
