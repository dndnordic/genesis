FROM python:3.10-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    gnupg \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/stable.txt" \
    && curl -LO "https://dl.k8s.io/release/$(cat stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl stable.txt

# Install Python dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Create directory structure
RUN mkdir -p /app/src/builder \
    /app/src/deployer \
    /app/configs \
    /app/kubernetes

# Copy application files
COPY src /app/src/
COPY configs /app/configs/
COPY kubernetes /app/kubernetes/

# Set Python path
ENV PYTHONPATH=/app

# Set working directory
WORKDIR /app

# Default command
CMD ["python", "-m", "src.builder.genesis_builder"]