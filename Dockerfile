FROM perl:5.38-slim

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install cpanm
RUN cpanm App::cpanminus --notest

# Copy dependency files first for better caching
COPY cpanfile .

# Install Perl dependencies (skip WWW::MetaForge - mounted at runtime)
RUN grep -v WWW::MetaForge cpanfile > cpanfile.docker && \
    cpanm --installdeps --notest --cpanfile cpanfile.docker . && \
    rm cpanfile.docker

# Install WWW::MetaForge dependencies (module itself is mounted). Keep in step
# with the requires of p5-www-metaforge's cpanfile.
RUN cpanm --notest Type::Tiny DateTime LWP::UserAgent LWP::Protocol::https \
    HTTP::Request Path::Tiny URI MooX::Cmd MooX::Options

# Copy application
COPY lib/ lib/
COPY bin/ bin/

# Make scripts executable
RUN chmod +x bin/*

# Run the HTTP server
CMD ["perl", "bin/mcp-arcraiders-http", "daemon", "-l", "http://*:3939"]
