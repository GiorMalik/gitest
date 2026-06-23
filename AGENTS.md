# gitest — GIOR Pentest Framework

## Deskripsi
gitest adalah pentest automation framework yang menggabungkan 250+ skill playbooks, 18 intelligence data layer, dan 109 tools catalog dalam satu pipeline terintegrasi untuk opencode.

## Struktur Proyek
- `GiScan/intelligence/` — 18 JSON intelligence files (vuln ontology, attack chains, WAF signatures, CVE correlations, tech correlations, port correlations, fuzzer data, patterns, endpoint patterns, verification patterns, escalation patterns, unified patterns, tools, tools_meta, skills, AB signals, waff bypass, file extensions)
- `GiScan/playbooks/` — 250 skill playbooks untuk berbagai attack vectors
- `GiScan/scripts/tools-catalog.json` — 109 security tools catalog
- `SCAN/targets/<domain>/` — Output directory (recon, loot, exploits, reports, screenshots, payloads)

## Environment
- `$GITEST_SCAN_DIR` — Optional override for scan output directory (default: $HOME/SCAN -> $(pwd)/SCAN)
- Command: `/gitest` — Entry point for pentest execution

## Rules
1. NEVER hardcode paths — always use dynamic SCAN_DIR resolution
2. Always refer to playbooks in GiScan/playbooks/ when handling specific vulnerability types
3. Output reports to SCAN/targets/<domain>/reports/ with CVSS scoring
