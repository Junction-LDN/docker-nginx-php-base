FROM php:8.3.13-fpm-alpine3.20 as base

ENV NGINX_VERSION 1.26.2
ENV NJS_VERSION   0.8.7
ENV PKG_RELEASE   1

ARG NGINX_CONF_FILE=./docker/nginx.conf

# install necessary alpine packages
RUN apk update && apk add --no-cache \
    zip \
    unzip \
    dos2unix \
    supervisor \
    lz4-dev \
    libpng-dev \
    libzip-dev \
    freetype-dev \
    $PHPIZE_DEPS \
    libjpeg-turbo-dev \
    icu-dev

# compile native PHP packages
RUN docker-php-ext-install \
    exif \
    gd \
    pcntl \
    bcmath \
    mysqli \
    pdo_mysql \
    intl

# configure packages
RUN docker-php-ext-configure gd --with-freetype --with-jpeg

# install additional packages from PECL
RUN pecl install zip && docker-php-ext-enable zip \
    && pecl install igbinary && docker-php-ext-enable igbinary \
    && yes | pecl install msgpack && docker-php-ext-enable msgpack \
    && yes | pecl install redis && docker-php-ext-enable redis

# install nginx
RUN set -x \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r2 \
        nginx-module-geoip=${NGINX_VERSION}-r2 \
        nginx-module-image-filter=${NGINX_VERSION}-r2 \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r1 \
    " \
    set -x \
    && KEY_SHA512="de7031fdac1354096d3388d6f711a508328ce66c168967ee0658c294226d6e7a161ce7f2628d577d56f8b63ff6892cc576af6f7ef2a6aa2e17c62ff7b6bf0d98 *stdin" \
    && apk add --no-cache --virtual .cert-deps \
        openssl \
    && wget -O /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
    && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
        echo "key verification succeeded!"; \
        mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
    else \
        echo "key verification failed!"; \
        exit 1; \
    fi \
    && apk del .cert-deps \
    && apk add -X "https://nginx.org/packages/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" --no-cache $nginxPackages

RUN echo -e "\n\n# Allow larger headers \n\
        fastcgi_buffers 16 32k; \n\
        fastcgi_buffer_size 128k; \n\
        fastcgi_busy_buffers_size 128k; \n\
        proxy_buffer_size   128k; \n\
        proxy_buffers   4 256k; \n\
        proxy_busy_buffers_size   256k;" >> /etc/nginx/fastcgi_params

RUN ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

# copy supervisor configuration
COPY ./docker/supervisord.conf /etc/supervisord.conf

EXPOSE 80

# run supervisor
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisord.conf"]
