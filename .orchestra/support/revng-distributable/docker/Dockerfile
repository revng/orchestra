FROM docker.io/library/ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        # Recompile needs crt{1,i,n}.o (libc6-dev)
        libc6-dev \
        # For debugging
        busybox curl bash \
        # Needed otherwise we'd get errors when, for example, when we fetch debug symbols
        ca-certificates && \
    rm -rf /root/.cache /var/lib/apt/lists/* /var/log/* /var/cache/*

COPY . /revng/
ENV PATH="${PATH}:/revng"
WORKDIR /revng

ARG CONFIG_JSON
RUN [ -f config.json ] || echo "$CONFIG_JSON" > config.json

# Sanity check
RUN revng --version
