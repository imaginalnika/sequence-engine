# Security

Keep credentials outside version control. If a question-judging callback uses a hosted service, use an authenticated proxy or short-lived credentials rather than embedding permanent API keys in a distributable client.

Validate graphs with `configure()` before starting a conversation. Host callbacks are responsible for enforcing application permissions and request timeouts.

Report security issues privately to the repository maintainer. Do not include credentials in public issues or logs.
