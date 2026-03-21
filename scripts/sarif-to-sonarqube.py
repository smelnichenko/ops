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
