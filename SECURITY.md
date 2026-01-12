# Security Policy

## Supported Versions

We release security updates for the current version only. Features and bug fixes are provided on a rolling release basis.

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < Latest | :x: |

If you're using an older version and discover a security issue, please upgrade to the latest version first. If upgrading isn't possible, please mention this in your report so we can understand your constraints.

## Reporting a Vulnerability

**Please DO NOT create public GitHub issues for security vulnerabilities.** Public disclosure of security issues before a fix is available can put users at risk.

### How to Report

We use GitHub's built-in Security Advisories for private vulnerability reporting:

1. Go to the [Security tab](https://github.com/AnjanJ/rails_error_dashboard/security/advisories/new)
2. Click "Report a vulnerability"
3. Fill out the form with as much detail as possible

### What to Include in Your Report

To help us understand and fix the issue quickly, please include:

- **Description:** Clear explanation of the vulnerability
- **Impact:** What could an attacker do with this vulnerability?
- **Steps to reproduce:** Detailed steps to demonstrate the issue
- **Affected versions:** Which versions are impacted (if known)
- **Suggested fix:** If you have ideas for how to fix it (optional but appreciated!)
- **Proof of concept:** Code or configuration demonstrating the vulnerability (if applicable)

### Response Timeline

- **Initial acknowledgment:** Within 7 days
- **Status updates:** We'll keep you informed of progress, with updates at least every 14 days
- **Fix timeline:** Depends on severity
  - Critical: 1-7 days
  - High: 7-30 days
  - Medium: 30-60 days
  - Low: 60-90 days

### What Happens Next

1. We'll confirm the vulnerability and assess its severity
2. We'll develop and test a fix
3. We'll prepare a security release
4. We'll coordinate disclosure with you (giving you credit if you'd like)
5. We'll release the fix and publish a security advisory

### Coordinated Disclosure

We follow responsible disclosure practices:

- We'll work with you to understand the issue
- We'll develop a fix before public disclosure
- We'll give you credit in the release notes (unless you prefer to remain anonymous)
- We'll publish a security advisory when the fix is released

### Security Best Practices for Users

When using Rails Error Dashboard:

- ✅ **Use HTTPS in production** - Always serve your dashboard over HTTPS
- ✅ **Enable authentication** - Don't expose the dashboard publicly without authentication
- ✅ **Keep updated** - Regularly update to the latest version
- ✅ **Review error data** - Be mindful of sensitive data in error logs
- ✅ **Use environment variables** - Store sensitive configuration securely
- ✅ **Configure ignored exceptions** - Use `ignored_exceptions` to prevent logging errors with sensitive data

### Questions or Concerns?

If you have questions about this security policy or need to discuss something that doesn't fit the reporting process above, you can reach out by:

- Creating a [GitHub Discussion](https://github.com/AnjanJ/rails_error_dashboard/discussions) for general security questions
- Emailing the maintainer directly (for sensitive matters that aren't vulnerabilities)

## Thank You

We deeply appreciate security researchers who help keep Rails Error Dashboard and its users safe. Your efforts make the open-source community more secure for everyone.
