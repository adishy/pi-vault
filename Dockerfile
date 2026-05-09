FROM node:22-slim

# Core utilities
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# PDF tools (poppler-utils)
# - pdfimages : extract embedded images from PDFs (use -j for JPEG output)
# - pdftotext : extract text layer (empty on image-based/scanned PDFs)
# - pdfinfo   : PDF metadata
# PI can read extracted images directly, so no OCR stack needed.
RUN apt-get update && apt-get install -y \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @earendil-works/pi-coding-agent@latest

COPY entrypoint.sh /entrypoint.sh
COPY generate-theme.sh /generate-theme.sh
RUN chmod +x /entrypoint.sh /generate-theme.sh

WORKDIR /vault
ENTRYPOINT ["/entrypoint.sh"]
