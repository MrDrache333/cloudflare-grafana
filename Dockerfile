# Use a lightweight base image such as debian or alpine
FROM debian:bullseye-slim

# Ensure required dependencies are installed
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    jq \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /usr/src/app

# Copy the bash script into the container
COPY cloudflare-analytics.sh /usr/src/app/scrape.sh

# Ensure the script is executable
RUN chmod +x /usr/src/app/scrape.sh

# Default entry point for the container: execute the bash script
ENTRYPOINT ["/usr/src/app/scrape.sh"]
