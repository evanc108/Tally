# ── Stage 1: Build ──────────────────────────────────────────────────────────────
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Cache dependency downloads before copying source.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o /tally .

# ── Stage 2: Runtime (distroless for minimal attack surface) ────────────────────
FROM gcr.io/distroless/static-debian12

COPY --from=builder /tally /tally

EXPOSE 8080

ENTRYPOINT ["/tally"]
