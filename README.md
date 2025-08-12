# AWS SSO Profile Manager (`aws-sso-profile`)

A CLI tool to automatically create and update AWS CLI profiles for every IAM role granted to your AWS SSO user.  
It supports importing session definitions from YAML, generating AWS CLI config profiles, and dry-running changes.

## Features

- **Bulk profile creation** from AWS SSO sessions
- **Import sessions** from a YAML file
- **Dry-run mode** to preview changes
- **Force overwrite** of existing sessions and profiles
- **Non-interactive mode** for scripts and automation

---

## Installation

### Homebrew (Recommended)

```bash
brew tap advantageous/tap
brew install aws-sso-profile
```

To upgrade later:
```bash
brew upgrade aws-sso-profile
```

---

## Usage

```bash
aws-sso-profile configure --import-file sessions.yaml
```

### Common Options

| Option | Description |
|--------|-------------|
| `--import-file <path>` | Path to YAML file containing SSO session definitions |
| `--dry-run` | Preview what changes would be made without applying them |
| `--non-interactive` | Run without prompting the user |
| `--force` | Overwrite existing sessions/profiles without confirmation |
| `--config-file <path>` | Custom path for sessions.yaml store |
| `--output-file <path>` | Custom AWS CLI config output path |

---

## Example Session YAML

```yaml
Advantageous:
  prefix: adv
  start_url: https://advantageous.awsapps.com/start
  sso_region: eu-central-1

OtherCompany:
  prefix: cp
  start_url: https://d-1234567890.awsapps.com/start
  sso_region: us-east-1
```

---

## Examples

### Import all sessions from a file
```bash
aws-sso-profile configure --import-file ./sessions.yaml
```

### Generate all sessions to you AWS config
```bash
aws-sso-profile generate
```

### Preview changes without applying
```bash
aws-sso-profile configure --import-file ./sessions.yaml --dry-run
```

### Force overwrite profiles
```bash
aws-sso-profile configure --import-file ./sessions.yaml --force
```

---

## License
MIT License – See [LICENSE](LICENSE) for details.
