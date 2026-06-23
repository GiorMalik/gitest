# gitest — GIOR Pentest Framework

> Autonomous penetration testing orchestration for OpenCode.  
> 250+ skill playbooks · 18 intelligence data layers · 109 security tools

## Overview

gitest is a comprehensive pentest automation framework that turns a single target URL into a full-chain exploitation pipeline. It combines a massive skill library, structured intelligence data, and dynamic tool orchestration to deliver submission-ready reports.

## Features

- **250+ Skill Playbooks** — Covering vulnerability classes, recon, post-exploitation, payloads, technology-specific attacks, protocols, and frameworks
- **18 Intelligence Data Layers** — Attack chains, WAF signatures, CVE correlations, tech correlations, vulnerability ontology, and more loaded at runtime
- **109 Security Tools** — From recon (subfinder, nmap) to exploitation (sqlmap, dalfox) to C2 (metasploit, sliver) and cloud (pacu, prowler)
- **Multi-Phase Pipeline** — 15+ phases: recon, OSINT, code analysis, CMS/CRM exploitation, API attacks, auth attacks, supply chain, cloud infra, data exfiltration simulation
- **Competitor Simulation** — Reports simulate what a real attacker/competitor would do with each finding
- **CVSS Scoring** — Every finding scored with CVSS v3.1

## Quick Start

```
/gitest https://target.example.com
```

## Structure

```
gitest/
├── GiScan/
│   ├── intelligence/       # 18 JSON data files
│   ├── playbooks/          # 250 skill playbooks
│   └── scripts/            # Tool catalog & automation
├── SCAN/
│   └── targets/<domain>/   # Pentest output
│       ├── recon/
│       ├── loot/
│       ├── exploits/
│       ├── reports/
│       ├── screenshots/
│       └── payloads/
└── AGENTS.md
```

## Requirements

- OpenCode CLI
- bash, curl, jq, python3
- Recommended: nmap, nuclei, ffuf, sqlmap, dalfox

## License

MIT
