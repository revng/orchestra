FROM ubuntu:22.04

COPY install-dependencies.sh \
     install-system-dependencies.sh \
     install-python-dependencies.sh \
     install-node-dependencies.sh \
     requirements.txt \
     /

RUN /install-dependencies.sh \
    && apt-get autoremove --yes --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -G sudo -m user && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER user
WORKDIR /home/user
