# stage 1: setup builder env
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git perl python3 make autoconf g++ flex bison \
    libgoogle-perftools-dev numactl perl-doc libfl-dev zlib1g-dev \
    ca-certificates help2man

WORKDIR /src
# compile verilator from source code
RUN git clone https://github.com/verilator/verilator && \
    cd verilator && \
    git checkout stable && \
    autoconf && \
    ./configure && \
    make -j$(nproc) && \
    make install


# stage 2: set up runtime env
FROM ubuntu:24.04 AS runtime

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    make \
    g++ \
    libgoogle-perftools4 \
    numactl \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/verilator* /usr/local/bin/
COPY --from=builder /usr/local/share/verilator /usr/local/share/verilator

RUN python3 -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir cocotb cocotb-test pytest

ENV VERILATOR_ROOT=/usr/local/share/verilator

WORKDIR /work
COPY rtl ./rtl/
COPY tests ./tests/

WORKDIR /work/tests

