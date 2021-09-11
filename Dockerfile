# Ref: https://github.com/wfg/docker-openvpn-client/blob/master/Dockerfile
FROM alpine:3.14

# Turning off all cases for vanilla deployment
ENV VPN_LOG_LEVEL=3 \
    HTTP_PROXY=off \
    SOCKS_PROXY=off

RUN apk add --no-cache \
        bind-tools \
        busybox-extras \
        dante-server \
        openvpn \
        bash\
        tinyproxy

RUN mkdir -p /data/vpn

COPY data/ /data

EXPOSE 1080 8080

HEALTHCHECK CMD ping -c 3 1.1.1.1 || exit 1

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

ENTRYPOINT ["/data/scripts/entry.sh"]
