# syntax=docker/dockerfile:1

###############################################################################
# PHP 8.4 + PHP-FPM + Nginx — image "batteries included" (dev / CI / deploy)
#
# Base image : serversideup/php:8.4-fpm-nginx  (Debian 13 "trixie", S6 Overlay)
# Ditambah   : git + git-lfs, SSH client (+ rsync), dan seluruh ekstensi PHP
#              yang bisa dikompilasi di PHP 8.4 — lewat mlocati/php-extension-installer
#
# Dokumentasi base image & env var (PHP_*, NGINX_*, SSL_MODE, dst.):
#   https://serversideup.net/open-source/docker-php/docs
###############################################################################

ARG PHP_VERSION=8.4
FROM serversideup/php:${PHP_VERSION}-fpm-nginx

# install-php-extensions + apt-get butuh root (base image berakhir sebagai www-data)
USER root

###############################################################################
# 1. Paket sistem: git, SSH client, dan utilitas pendamping
###############################################################################
RUN docker-php-serversideup-dep-install-debian \
        ca-certificates \
        git \
        git-lfs \
        less \
        openssh-client \
        rsync

# Mounted volume (bind mount dari host) biasanya milik UID lain, sehingga git
# menolak repo-nya dengan error "dubious ownership" tanpa safe.directory ini.
RUN git config --system --add safe.directory '*'

# ~/.ssh untuk user www-data: HOME=/var/www (dipakai juga oleh git saat clone via SSH).
RUN install -d -o www-data -g www-data -m 0700 /var/www/.ssh \
    && printf 'Host *\n    StrictHostKeyChecking accept-new\n' > /var/www/.ssh/config \
    && chown www-data:www-data /var/www/.ssh/config \
    && chmod 0600 /var/www/.ssh/config

###############################################################################
# 2. Ekstensi PHP
#
# Installer bawaan base image bisa lebih tua dari rilis terbaru; ambil versi
# terbaru dari image resmi mlocati agar semua ekstensi terbaru ikut ter-support.
###############################################################################
COPY --from=mlocati/php-extension-installer:2.12.0 /usr/bin/install-php-extensions /usr/local/bin/

RUN install-php-extensions \
        # --- dasar / system ---
        bcmath calendar exif ffi ftp gettext shmop sockets sysvmsg sysvsem sysvshm \
        tidy translit uuid xattr \
        # --- database ---
        dba memcache memcached mongodb mysqli odbc pdo_dblib pdo_firebird \
        pdo_odbc pdo_pgsql pdo_sqlsrv pgsql pq sqlsrv \
        # --- format & struktur data ---
        bitset brotli bz2 csv decimal ds igbinary ion jsonpath judy lz4 lzf \
        mailparse md4c msgpack php_trie protobuf psr simdjson snappy yaml zstd \
        # --- imaging & i18n ---
        gd gmagick imagick vips intl pspell \
        # --- XML ---
        soap xmldiff xmlrpc xsl \
        # --- kripto & keamanan ---
        gnupg mcrypt oauth ssh2 snuffleupagus \
        # --- network & messaging ---
        amqp ast event ev gearman grpc http inotify ip2location luasandbox \
        maxminddb nsq openswoole rdkafka smbclient snmp solr stomp uv yar zmq \
        zookeeper \
        # --- profiling & tuning ---
        excimer opentelemetry pcov spx xdebug xdiff xhprof yac

###############################################################################
# 3. Kembalikan user default base image
###############################################################################
USER www-data
