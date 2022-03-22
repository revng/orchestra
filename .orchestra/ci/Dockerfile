FROM ubuntu:18.04

COPY install-dependencies.sh /install-dependencies.sh
COPY install-system-dependencies.sh /install-system-dependencies.sh
COPY install-python-dependencies.sh /install-python-dependencies.sh

RUN /install-dependencies.sh \
    && apt-get autoremove --yes --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
