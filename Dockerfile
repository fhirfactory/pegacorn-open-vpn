# Ref: https://github.com/wfg/docker-openvpn-client/blob/master/Dockerfile
FROM fhirfactory/pegacorn-base-openvpn:1.0.0

# Turning off all cases for vanilla deployment

RUN mkdir -p /data/vpn

COPY data/ /data

EXPOSE 1080 8080

HEALTHCHECK CMD ping -c 3 1.1.1.1 || exit 1

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

RUN chmod +x /data/scripts/entry.sh

ENTRYPOINT ["/data/scripts/entry.sh"]
