# Ansible-lint → SonarQube Integration Plan

## Goal

Surface ansible-lint findings in SonarQube's dashboard alongside existing code quality metrics. ansible-lint has deep Ansible knowledge (deprecated modules, unsafe practices, Jinja2 issues, role structure) that SonarQube's generic YAML analysis misses.

## Current State

- **Infra SonarQube project** (`monitor-infra`): scans `deploy/`, `.github/`, Dockerfiles for generic YAML/Dockerfile issues
- **CI infra job**: runs `helm lint` + `sonarqube-scanner` on infra changes
- **Runner** (`ten`): has Python 3.13, pip3, yamllint 1.37.1; no ansible-lint installed
- **Ansible files**: `deploy/ansible/` — 6 playbooks, 1 role, inventory, vars

## Approach

### SonarQube Generic Issue Import

SonarQube supports importing external analyzer results via the [Generic Issue Import Format](https://docs.sonarsource.com/sonarqube/latest/analyzing-source-code/importing-external-issues/generic-issue-import-format/). We:

1. Run `ansible-lint` with SARIF output (`-f sarif`)
2. Convert SARIF to SonarQube's generic issue JSON format
3. Pass the report to sonar-scanner via `sonar.externalIssuesReportPaths`

### Why SARIF → SQ JSON (not direct JSON)?

ansible-lint natively outputs SARIF (standardized static analysis format). SonarQube doesn't import SARIF directly, so we convert with a small Python script. This is more robust than parsing ansible-lint's codeclimate/JSON formats, which have changed across versions.

## Implementation

### Step 1: Install ansible-lint on Runner

```bash
# On ten (runner host) — PEP 668 requires pipx
pipx install ansible-lint
```

ansible-lint pulls in its own dependencies (ansible-core, yamllint, etc.). pipx installs it in `~/.local/bin/` which is already on the runner's PATH.

### Step 2: Create `.ansible-lint` Config

At `deploy/ansible/.ansible-lint`:

```yaml
profile: production
exclude_paths:
  - venv/
  - .cache/
  - vars/vault-pi-runtime.yml
kinds:
  - playbook: "playbooks/*.yml"
  - playbook: "deploy.yml"
  - playbook: "uninstall.yml"
  - vars: "vars/*.yml"
  - tasks: "roles/*/tasks/*.yml"
  - handlers: "roles/*/handlers/*.yml"
  - meta: "roles/*/meta/*.yml"
```

The `production` profile enables all rules including those that enforce best practices for production playbooks.

### Step 3: Create SARIF → SonarQube Converter Script

At `scripts/sarif-to-sonarqube.py`:

```python
#!/usr/bin/env python3
"""Convert SARIF output to SonarQube Generic Issue Import format."""
import json
import sys

SEVERITY_MAP = {
    "error": "CRITICAL",
    "warning": "MAJOR",
    "note": "MINOR",
    "none": "INFO",
}

def convert(sarif_path, output_path, path_prefix=""):
    with open(sarif_path) as f:
        sarif = json.load(f)

    issues = []
    for run in sarif.get("runs", []):
        tool_name = run.get("tool", {}).get("driver", {}).get("name", "ansible-lint")
        for result in run.get("results", []):
            rule_id = result.get("ruleId", "unknown")
            message = result.get("message", {}).get("text", "")
            level = result.get("level", "warning")

            for location in result.get("locations", []):
                phys = location.get("physicalLocation", {})
                artifact = phys.get("artifactLocation", {}).get("uri", "")
                region = phys.get("region", {})
                start_line = region.get("startLine", 1)

                file_path = path_prefix + artifact if path_prefix else artifact

                issues.append({
                    "engineId": tool_name,
                    "ruleId": rule_id,
                    "severity": SEVERITY_MAP.get(level, "MAJOR"),
                    "type": "CODE_SMELL",
                    "primaryLocation": {
                        "message": message,
                        "filePath": file_path,
                        "textRange": {"startLine": start_line},
                    },
                })

    with open(output_path, "w") as f:
        json.dump({"issues": issues}, f, indent=2)

    print(f"Converted {len(issues)} issues to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <sarif-input> <sonarqube-output> [path-prefix]")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
```

### Step 4: Update CI Workflow

Add ansible-lint step to the infra job in `.github/workflows/ci.yml`:

```yaml
infra:
  needs: changes
  if: needs.changes.outputs.helm == 'true' || needs.changes.outputs.infra == 'true'
  runs-on: self-hosted
  steps:
    - name: Setup toolchain
      run: |
        . "$HOME/.nvm/nvm.sh" 2>/dev/null || true
        echo "PATH=$HOME/.local/bin:$PATH" >> "$GITHUB_ENV"

    - uses: actions/checkout@v4

    - name: Lint Helm chart
      if: needs.changes.outputs.helm == 'true'
      working-directory: infra/helm
      run: helm lint .

    - name: Run ansible-lint
      if: needs.changes.outputs.infra == 'true'
      working-directory: deploy/ansible
      run: ansible-lint -f sarif --nocolor > ../../ansible-lint.sarif 2>/dev/null || true

    - name: Convert ansible-lint to SonarQube format
      if: needs.changes.outputs.infra == 'true'
      run: python3 scripts/sarif-to-sonarqube.py ansible-lint.sarif ansible-lint-sonar.json deploy/ansible/

    - name: Infrastructure sonar analysis
      if: needs.changes.outputs.infra == 'true'
      env:
        SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
      run: >-
        npx sonarqube-scanner
        -Dsonar.projectBaseDir=.
        -Dsonar.externalIssuesReportPaths=ansible-lint-sonar.json
```

### Step 5: Update `sonar-project.properties`

Add `deploy/ansible` to sources if not already covered (it is — `deploy` is listed).

No changes needed. The `sonar.sources=deploy,.github,backend,frontend` already includes `deploy/ansible/`.

## File Paths

| File | Purpose |
|------|---------|
| `deploy/ansible/.ansible-lint` | ansible-lint configuration |
| `scripts/sarif-to-sonarqube.py` | SARIF → SQ generic issue converter |
| `.github/workflows/ci.yml` | CI pipeline (add ansible-lint step) |
| `.github/workflows/cd.yml` | CD pipeline (add ansible-lint step, no quality gate wait) |

## Testing

1. Install ansible-lint on runner: `pip3 install --user ansible-lint`
2. Push branch → CI triggers infra job
3. Verify ansible-lint runs and produces SARIF output
4. Verify converter produces valid SonarQube JSON
5. Verify issues appear in SonarQube dashboard under `monitor-infra` project

## Rollback

- ansible-lint step uses `|| true` so failures don't block CI
- External issues are informational in SonarQube (don't affect quality gate)
- Remove the CI steps and `.ansible-lint` config to fully rollback
