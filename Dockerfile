# syntax=docker/dockerfile:1

###############################################################################
# PHP 8.4 + PHP-FPM + Nginx — varian ramping (dev / CI / deploy)
#
# Base image : serversideup/php:8.4-fpm-nginx  (Debian 13 "trixie", S6 Overlay)
# Base sudah memuat — tidak perlu dipasang ulang:
#   opcache pcntl pdo_mysql pdo_pgsql pdo_sqlite redis zip sodium
#   curl mbstring iconv json mysqlnd openssl posix xml* zlib
#   (verifikasi: docker run --rm --entrypoint php <image> -m)
#
# Target build:
#   production (default) → hanya ekstensi yang dipakai aplikasi umum
#   dev                  → production + tooling development (xdebug, ast)
#
#   docker build -t <user>/<repo>:latest .
#   docker build --target dev -t <user>/<repo>:dev .
#
# Dokumentasi base image & env var (PHP_*, NGINX_*, SSL_MODE, dst.):
#   https://serversideup.net/open-source/docker-php/docs
###############################################################################

ARG PHP_VERSION=8.4

###############################################################################
# Stage: base — paket sistem + installer ekstensi (dipakai semua target)
###############################################################################
FROM serversideup/php:${PHP_VERSION}-fpm-nginx AS base

# install-php-extensions + apt-get butuh root (base image berakhir sebagai www-data)
USER root

# Paket sistem: git, SSH client, dan utilitas pendamping.
# WAJIB satu argumen dipisah koma: helper ini hanya membaca "$1", sehingga
# paket kedua dan seterusnya akan diabaikan bila ditulis sebagai arg berpisah.
RUN docker-php-serversideup-dep-install-debian \
        "ca-certificates,git,git-lfs,less,openssh-client,rsync"

# Mounted volume (bind mount dari host) biasanya milik UID lain, sehingga git
# menolak repo-nya dengan error "dubious ownership" tanpa safe.directory ini.
RUN git config --system --add safe.directory '*'

# ~/.ssh untuk user www-data: HOME=/var/www (dipakai juga oleh git saat clone via SSH).
RUN install -d -o www-data -g www-data -m 0700 /var/www/.ssh \
    && printf 'Host *\n    StrictHostKeyChecking accept-new\n' > /var/www/.ssh/config \
    && chown www-data:www-data /var/www/.ssh/config \
    && chmod 0600 /var/www/.ssh/config

# Installer bawaan base image bisa lebih tua dari rilis terbaru; ambil versi
# terbaru dari image resmi mlocati agar semua ekstensi terbaru ikut ter-support.
COPY --from=mlocati/php-extension-installer:2.12.0 /usr/bin/install-php-extensions /usr/local/bin/

###############################################################################
# Stage: runtime — ekstensi untuk aplikasi produksi
#
# Override daftar ini dengan: --build-arg PHP_EXTENSIONS_PROD="intl gd ..."
# ── i18n/format       : intl
# ── matematika        : bcmath gmp
# ── imaging           : exif gd imagick
# ── database          : mysqli  (pdo_mysql/pdo_pgsql sudah ada di base)
# ── serialisasi/cache : igbinary
# ── web service       : soap
# ── umum              : sockets uuid yaml
#
# TIDAK dipasang default — tambahkan lewat --build-arg hanya jika butuh:
# ── SQL Server  : pdo_sqlsrv sqlsrv        ── NoSQL      : mongodb
# ── messaging   : amqp rdkafka             ── API/RPC    : protobuf grpc
# ── observability: opentelemetry           ── XML lanjut : xsl
# ── serialisasi : msgpack                  ── legacy/niche: ftp imap gettext tidy calendar dba snmp ssh2 inotify
# ── usang/mati  : xmlrpc mcrypt memcache pq pdo_dblib pdo_firebird xhprof
###############################################################################
FROM base AS runtime

# Metadata OCI — tampil di halaman Docker Hub.
# Semua bisa dioverride saat build, contoh:
#   --build-arg IMAGE_VERSION=1.0.0 --build-arg IMAGE_LICENSE=MIT
ARG PHP_VERSION
ARG IMAGE_TITLE="PHP ${PHP_VERSION} + PHP-FPM + Nginx"
ARG IMAGE_DESCRIPTION="serversideup/php dengan set ekstensi PHP yang dikurasi untuk aplikasi umum — tanpa ekstensi usang/niche, siap deploy."
ARG IMAGE_VERSION="0.1.0"
ARG IMAGE_LICENSE="GPL-3.0-or-later"
ARG IMAGE_AUTHORS="yllumi"
LABEL org.opencontainers.image.title="${IMAGE_TITLE}" \
      org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="${IMAGE_LICENSE}" \
      org.opencontainers.image.authors="${IMAGE_AUTHORS}" \
      org.opencontainers.image.base.name="docker.io/serversideup/php:${PHP_VERSION}-fpm-nginx"

ARG PHP_EXTENSIONS_PROD="bcmath exif gd gmp igbinary imagick intl mysqli soap sockets uuid yaml"
RUN install-php-extensions ${PHP_EXTENSIONS_PROD}

###############################################################################
# Stage: dev — runtime + tooling development (JANGAN dipakai di produksi)
#
# xdebug : step debugging & code coverage
# ast    : dibutuhkan sebagian alat analisis statis
# Alternatif opsional: pcov (coverage lebih cepat dari xdebug), spx (profiler)
###############################################################################
FROM runtime AS dev

ARG PHP_EXTENSIONS_DEV="xdebug ast"
RUN install-php-extensions ${PHP_EXTENSIONS_DEV}

# Xdebug 3 membaca env ini dan menang atas nilai di php.ini, jadi cukup
# dioverride saat runtime: -e XDEBUG_MODE=debug,coverage
ENV XDEBUG_MODE="develop"

USER www-data

###############################################################################
# Stage: production — dipakai sebagai target default `docker build`
#
# Perlu alias terpisah karena stage terakhir di file ini yang jadi target
# default, sementara `dev` harus berada di atasnya.
###############################################################################
FROM runtime AS production

USER www-data
