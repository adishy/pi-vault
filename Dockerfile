FROM node:22-slim

RUN apt-get update && apt-get install -y git python3 && rm -rf /var/lib/apt/lists/*

RUN npm install -g @earendil-works/pi-coding-agent@latest

COPY entrypoint.sh /entrypoint.sh
COPY generate-theme.sh /generate-theme.sh
RUN chmod +x /entrypoint.sh /generate-theme.sh

WORKDIR /vault
ENTRYPOINT ["/entrypoint.sh"]
