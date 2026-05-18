# Matrix code in x86_64/aarch64 assembly ~10KB image.
FROM alpine:3.19 AS builder
ARG TARGETARCH
RUN apk add --no-cache binutils
COPY matrix-${TARGETARCH}.s /tmp/matrix.s
RUN as -o /tmp/matrix.o /tmp/matrix.s && \
    ld -s -o /tmp/matrix /tmp/matrix.o && \
    strip --strip-all /tmp/matrix

FROM scratch
LABEL org.opencontainers.image.source="https://github.com/zdk/matrix"
LABEL org.opencontainers.image.description="Matrix-style digital rain in x86_64/aarch64 assembly ~10KB scratch image."
LABEL org.opencontainers.image.licenses="MIT"
COPY --from=builder /tmp/matrix /matrix
ENTRYPOINT ["/matrix"]
