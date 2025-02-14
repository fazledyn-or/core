ARG BASE_IMAGE
FROM $BASE_IMAGE
ARG FIXUP=echo
MAINTAINER OCR-D
ENV DEBIAN_FRONTEND noninteractive
ENV PYTHONIOENCODING utf8
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV PIP=pip

WORKDIR /build-ocrd
COPY ocrd ./ocrd
COPY ocrd_modelfactory ./ocrd_modelfactory/
COPY ocrd_models ./ocrd_models
COPY ocrd_utils ./ocrd_utils
RUN mv ./ocrd_utils/ocrd_logging.conf /etc
COPY ocrd_validators/ ./ocrd_validators
COPY ocrd_network/ ./ocrd_network
COPY Makefile .
COPY README.md .
COPY LICENSE .
RUN echo 'APT::Install-Recommends "0"; APT::Install-Suggests "0";' >/etc/apt/apt.conf.d/ocr-d.conf
RUN apt-get update && apt-get -y install software-properties-common \
    && apt-get update && apt-get -y install \
        ca-certificates \
        python3-dev \
        python3-venv \
        gcc \
        make \
        wget \
        time \
        curl \
        sudo \
        git \
    && make deps-ubuntu \
    && python3 -m venv /usr/local \
    && hash -r \
    && pip install --upgrade pip setuptools wheel \
    && make install \
    && eval $FIXUP \
    && rm -rf /build-ocrd

WORKDIR /data

CMD ["/usr/local/bin/ocrd", "--help"]
