# OdionChat image for Azure Container Apps.
#
# Local build + run:  ./azure/start.sh
# Build + push GHCR:  ./azure/push_image.sh
# CI:                 .github/workflows/docker-publish.yml → ghcr.io/manavanl/odionchat

FROM ghcr.io/open-webui/open-webui@sha256:60fa63e738e7dc5e548f26a54d6deac684d6712256a7fae91dd6157ce64bef84

COPY config/ /config/
COPY scripts/entrypoint.sh /entrypoint.sh
COPY azure/patch-locale.sh /patch-locale.sh

RUN chmod +x /entrypoint.sh /patch-locale.sh \
  && /patch-locale.sh

ENTRYPOINT ["bash", "/entrypoint.sh"]
