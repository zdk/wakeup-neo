# Matrix code in x86_64/aarch64 assembly ~10KB image.
FROM alpine:3.19 AS builder
ARG TARGETARCH
RUN apk add --no-cache binutils
COPY matrix-${TARGETARCH}.s /tmp/matrix.s
RUN as -o /tmp/matrix.o /tmp/matrix.s && \
    ld -z noseparate-code --build-id=none -s \
       -o /tmp/matrix /tmp/matrix.o && \
    strip --strip-all /tmp/matrix && \
    objcopy -R .comment -R .note.gnu.build-id -R .note.gnu.property /tmp/matrix

FROM scratch
LABEL org.opencontainers.image.source="https://github.com/zdk/wakeup-neo"
COPY --from=builder /tmp/matrix /matrix
ENTRYPOINT ["/matrix"]
