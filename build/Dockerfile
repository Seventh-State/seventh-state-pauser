FROM hexpm/elixir:1.14.5-erlang-26.2.5.13-alpine-3.22.1

# Install build tools
RUN apk add --no-cache \
    bash \
    build-base \
    curl \
    gawk \
    git \
    jq \
    make \
    p7zip \
    python3 \
    rsync \
    unzip \
    zip

RUN ln -sf /usr/bin/gawk /usr/bin/awk

WORKDIR /app
COPY . .

# Default command (can be overridden)
CMD ["bash"]
