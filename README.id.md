# gitest — GIOR Pentest Framework

> Orkestrasi penetration testing otonom untuk OpenCode.  
> 250+ skill playbooks · 18 lapisan data intelijen · 109 tools keamanan

## Gambaran Umum

gitest adalah framework pentest automation yang mengubah satu URL target menjadi pipeline eksploitasi rantai penuh. Framework ini menggabungkan pustaka skill yang masif, data intelijen terstruktur, dan orkestrasi tools dinamis untuk menghasilkan laporan yang siap dikirim.

## Fitur

- **250+ Skill Playbooks** — Meliputi kelas kerentanan, recon, post-exploitation, payload, serangan spesifik teknologi, protokol, dan framework
- **18 Lapisan Data Intelijen** — Attack chains, signature WAF, korelasi CVE, korelasi teknologi, ontologi kerentanan, dan lainnya yang dimuat saat runtime
- **109 Security Tools** — Dari recon (subfinder, nmap) hingga eksploitasi (sqlmap, dalfox) hingga C2 (metasploit, sliver) dan cloud (pacu, prowler)
- **Pipeline Multi-Fase** — 15+ fase: recon, OSINT, analisis kode, eksploitasi CMS/CRM, serangan API, serangan auth, supply chain, cloud infra, simulasi data exfiltration
- **Simulasi Kompetitor** — Laporan mensimulasikan apa yang akan dilakukan attacker/kompetitor nyata terhadap setiap temuan
- **Skor CVSS** — Setiap temuan diberi skor dengan CVSS v3.1

## Mulai Cepat

```
/gitest https://target.example.com
```

## Struktur

```
gitest/
├── GiScan/
│   ├── intelligence/       # 18 file data JSON
│   ├── playbooks/          # 250 skill playbooks
│   └── scripts/            # Katalog tools & automasi
├── SCAN/
│   └── targets/<domain>/   # Output pentest
│       ├── recon/
│       ├── loot/
│       ├── exploits/
│       ├── reports/
│       ├── screenshots/
│       └── payloads/
└── AGENTS.md
```

## Persyaratan

- OpenCode CLI
- bash, curl, jq, python3
- Disarankan: nmap, nuclei, ffuf, sqlmap, dalfox

## Lisensi

MIT
