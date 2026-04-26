# Security Policy

## Supported Versions

Only the latest released container image is supported for security fixes:

```text
ghcr.io/newcoderlife/xtunnel:latest
```

Older tags may be removed or left unsupported.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Report vulnerabilities privately by email:

```text
newcoderlife@gmail.com
```

Include:

- affected image tag or commit
- deployment mode: server or client
- relevant environment variables with secrets redacted
- reproduction steps
- expected impact

I will try to acknowledge reports within 7 days and publish a fixed release when a confirmed issue affects supported xtunnel images.

For vulnerabilities in upstream Xray-core, Caddy, Alpine, or RouterOS, also report them to the upstream project. If xtunnel packaging or defaults make the issue exploitable, please still report it here.
