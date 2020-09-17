FROM ubuntu:18.04

COPY install-dependencies.sh /install-dependencies.sh

RUN /install-dependencies.sh \
    && apt-get autoremove --yes --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
