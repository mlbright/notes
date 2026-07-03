# Caddy configuration (runs on a separate machine)

Caddy is **not** installed on the app machine. It runs on a separate host and
reverse-proxies to this machine's Thruster listener (port 3002) over
Tailscale. TLS terminates at Caddy; the app trusts `X-Forwarded-Proto`
(`config.assume_ssl` / `config.force_ssl` are enabled in production).

Add to the Caddy machine's `/etc/caddy/Caddyfile`, replacing the domain and
the app machine's Tailscale hostname:

```caddyfile
notes.example.com {
	reverse_proxy app-machine.tailnet-name.ts.net:3002

	# Match the app's attachment size limit
	request_body {
		max_size 25MB
	}
}
```

Notes:

- `reverse_proxy` sends `X-Forwarded-Proto` and preserves the original `Host`
  header by default — both are required (the app checks `Host` against
  `APP_HOST` from `web/.env`).
- Thruster on the app machine handles asset caching and compression, so no
  `file_server` / asset-path configuration is needed here.
- Health check endpoint: `http://app-machine:3002/up`.
