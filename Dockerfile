##
# Send
#
# License https://gitlab.com/timvisee/send/blob/master/LICENSE
##

# Build project
FROM node:16.13-alpine3.13 AS builder

RUN set -x \
  # Change node uid/gid
  && apk --no-cache add shadow \
  && groupmod -g 1001 node \
  && usermod -u 1001 -g 1001 node

RUN set -x \
    # Add user
    && addgroup --gid 1000 app \
    && adduser --disabled-password \
        --gecos '' \
        --ingroup app \
        --home /app \
        --uid 1000 \
        app

COPY --chown=app:app . /app

USER app
WORKDIR /app

RUN set -x \
    # Build
    && PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true npm ci \
    && npm run build

# Main image
FROM node:16.13-alpine3.13

RUN set -x \
  # Change node uid/gid
  && apk --no-cache add shadow \
  && groupmod -g 1001 node \
  && usermod -u 1001 -g 1001 node

RUN set -x \
    # Add user
    && addgroup --gid 1000 app \
    && adduser --disabled-password \
        --gecos '' \
        --ingroup app \
        --home /app \
        --uid 1000 \
        app

USER app
WORKDIR /app

COPY --chown=app:app package*.json ./ 
COPY --chown=app:app app app
COPY --chown=app:app common common
COPY --chown=app:app public/locales public/locales
COPY --chown=app:app server server
COPY --chown=app:app --from=builder /app/dist dist

RUN npm ci --production && npm cache clean --force
RUN mkdir -p /app/.config/configstore
RUN ln -s dist/version.json version.json

# Install cloudflared
USER root
RUN set -x \
  && apk update \
  && apk add --no-cache wget bash \
  && wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  && chmod +x /usr/local/bin/cloudflared \
  && apk clean

# Set up cloudflared tunnel with the provided token
RUN set -x \
  && cloudflared tunnel login --token eyJhIjoiZjVlMDBmZWE3MzdlMTAzMGEwOTMyNmNiZTQ0MGJkNzEiLCJ0IjoiNWQxMzg2MTgtNmExNy00ZTk1LTllZDctMmNmNmI0NDE4ZDc3IiwicyI6IlpEVmtORGM0T0dRdE16TXlZaTAwT1dVeExXRXpaamN0WWpnd1pqazVaRFUxWmpnMyJ9 \
  && cloudflared tunnel create dergo-tunnel \
  && cloudflared tunnel route dns dergo-tunnel dergo.postieri.digital

# Set environment variables for cloudflared and the app
ENV PORT=1443
EXPOSE ${PORT}

# Start cloudflared tunnel and your app
CMD ["sh", "-c", "cloudflared tunnel run dergo-tunnel & node server/bin/prod.js"]
