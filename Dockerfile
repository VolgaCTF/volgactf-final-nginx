FROM ubuntu:24.04 AS build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libpcre3-dev \
    zlib1g-dev \
    libssl-dev \
    libxml2-dev \
    libxslt-dev \
    libbrotli-dev \
    wget \
    unzip \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*


# Set versions (pinning for reproducibility)
ENV NGINX_VERSION=1.29.1
ENV NJS_VERSION=0.9.1

WORKDIR /usr/src

# Download Nginx
RUN wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
    && tar -xvzf nginx-${NGINX_VERSION}.tar.gz

# Download Brotli module
RUN git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli.git && cd ngx_brotli && git checkout a71f9312c2deb28875acc7bacfdd5695a111aa53

# Download NJS (nginx-js)
RUN git clone --depth 1 --branch ${NJS_VERSION} https://github.com/nginx/njs.git

# Build Nginx with modules
WORKDIR /usr/src/nginx-${NGINX_VERSION}
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --pid-path=/var/run/nginx/nginx.pid \
    --lock-path=/var/run/nginx/nginx.lock \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --with-file-aio \
    --with-threads \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --add-module=/usr/src/ngx_brotli \
    --add-module=/usr/src/njs/nginx \
    && make && make install

# Final runtime image
FROM ubuntu:24.04
LABEL maintainer="VolgaCTF"

ARG UID=2600
ARG GID=2600
ARG BUILD_DATE
ARG BUILD_VERSION
ARG VCS_REF

LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="volgactf-final-nginx"
LABEL org.label-schema.description="VolgaCTF Final nginx – provides a Dockerfile with a custom built Nginx"
LABEL org.label-schema.url="https://volgactf.ru/en"
LABEL org.label-schema.vcs-url="https://github.com/VolgaCTF/volgactf-final-nginx"
LABEL org.label-schema.vcs-ref=$VCS_REF
LABEL org.label-schema.version=$BUILD_VERSION

RUN apt-get update && apt-get install -y \
    libpcre3 \
    zlib1g \
    libssl3 \
    libxml2 \
    libbrotli1 \
    && rm -rf /var/lib/apt/lists/*

# Copy Nginx from build stage
COPY --from=build /usr/sbin/nginx /usr/sbin/nginx
COPY --from=build /etc/nginx /etc/nginx
COPY --from=build /var/log/nginx /var/log/nginx

# Create necessary dirs and change permissions
RUN mkdir -p /var/cache/nginx /var/run/nginx \
    && groupadd -g ${GID} -r nginx \
    && useradd -u ${UID} -r -g nginx -d /nonexistent -s /sbin/nologin nginx \
    && chown -R nginx:nginx /etc/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/run/nginx \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
