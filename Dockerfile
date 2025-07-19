# --- ALAC BUILD STAGE (for Shairport Sync) ---
# Inherits from builder-base
FROM builder-base AS builder-alac

WORKDIR /tmp/alac
RUN git clone https://github.com/mikebrady/alac . && \
    autoreconf -fi && \
    ./configure && \
    make && \
    make install

# --- SHAIRPORT SYNC BUILD STAGE ---
# Inherits from builder-base
FROM builder-base AS builder-sps

ARG SHAIRPORT_SYNC_BRANCH=master

# Ensure these COPY --from statements are correct
COPY --from=builder-alac /usr/local/lib/libalac.* /usr/local/lib/
COPY --from=builder-alac /usr/local/lib/pkgconfig/alac.pc /usr/local/lib/pkgconfig/
COPY --from=builder-alac /usr/local/include /usr/local/include

WORKDIR /tmp/shairport-sync
RUN git clone https://github.com/mikebrady/shairport-sync . && \
    git checkout "$SHAIRPORT_SYNC_BRANCH" && \
    autoreconf -fi && \
    ./configure \
        --with-alsa \
        --with-dummy \
        --with-pipe \
        --with-stdout \
        --with-avahi \
        --with-ssl=mbedtls \
        --with-soxr \
        --sysconfdir=/etc \
        --with-dbus-interface \
        --with-mpris-interface \
        --with-mqtt-client \
        --with-apple-alac \
        --with-convolution && \
    make -j $(nproc) && \
    make install

# --- OWNTONE BUILD STAGE ---
# Inherits from builder-base
FROM builder-base AS builder-owntone

ARG DISABLE_UI_BUILD
ARG REPOSITORY_URL=https://github.com/owntone/owntone-server.git
ARG REPOSITORY_BRANCH=master
ARG REPOSITORY_COMMIT
ARG REPOSITORY_VERSION

WORKDIR /tmp/source

RUN git clone -b ${REPOSITORY_BRANCH} ${REPOSITORY_URL} ./ && \
    if [ "${REPOSITORY_COMMIT}" ]; then git checkout "${REPOSITORY_COMMIT}"; \
    elif [ "${REPOSITORY_VERSION}" ]; then git checkout tags/"${REPOSITORY_VERSION}"; fi && \
    if [ -z "${DISABLE_UI_BUILD}" ]; then cd web-src; npm install; npm run build; cd ..; fi && \
    autoreconf -i && \
    ./configure \
        --disable-install_systemd \
        --disable-install_user \
        --enable-chromecast \
        --enable-silent-rules \
        --infodir=/usr/share/info \
        --localstatedir=/var \
        --mandir=/usr/share/man \
        --prefix=/usr \
        --sysconfdir=/etc/owntone && \
    make DESTDIR=/tmp/build install && \
    cd /tmp/build && \
    install -D etc/owntone/owntone.conf usr/share/doc/owntone/examples/owntone.conf && \
    rm -rf var etc

# --- RUNTIME STAGE ---
# This is the final image base
FROM alpine:3.21 AS runtime