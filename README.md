# 🔍 Tech Stack Detector

> A modern, Full-Stack web technology fingerprinting tool that identifies the technologies powering any website.

`Python 3.10+ (FastAPI)` · `Flutter (Dart)` · `MIT License` · `200 domains tested` · `127 / 477 unique technologies found`

---

## Overview

Tech Stack Detector crawls a list of domains and fingerprints the technologies they use — from JavaScript frameworks and analytics tools to CDNs, CMS platforms, and e-commerce solutions.

Built as part of a technical challenge, I decided to go beyond a simple CLI script and implemented a **Full-Stack Client-Server Architecture**:

- **Backend (Engine)** — A fast asynchronous API built with Python & FastAPI. It handles the heavy lifting: HTTP requests, DNS resolution, robots.txt parsing, and pattern matching.
- **Frontend (UI)** — A responsive, cross-platform Flutter application that provides a clean, real-time dashboard for users to upload domain lists, track scanning progress, and view statistics instantly without freezing the UI.

---

## Results

| Metric | Value |
|---|---|
| Domains scanned | 200 |
| Unique technologies detected | 127 / 477 |
| Total technology occurrences | 1324 |
| Detection rate | ~27% |
| Output format | JSON (technology name + evidence per domain) |

Every detected technology includes an **`evidence` field** (e.g., matching a specific HTTP header, JS variable, or HTML meta tag) to justify how the conclusion was reached.

---

## How It Works

The backend performs **multi-signal fingerprinting** by examining multiple layers of the target website:

- **HTTP response headers** — Inspecting `X-Powered-By`, `Server`, `Set-Cookie`, and custom vendor headers.
- **HTML DOM Keywords & Meta tags** — Scanning the raw HTML source code for specific generator tags, keywords, and external JS script `src` inclusions.
- **JavaScript globals** — Detecting global objects injected by frameworks (e.g., `window.__NEXT_DATA__`, `window.Shopify`, `window.gtag`).
- **DNS records** — Resolving MX, TXT, and CNAME records to identify email providers (e.g., Google Workspace), marketing tools, and CDNs.
- **robots.txt & sitemap.xml** — Fetching hidden paths to detect underlying CMS platforms (e.g., WordPress `wp-admin` or Magento-specific routes).
- **Wappalyzer Signature Engine** — Running hundreds of regex rules against the gathered data to accurately identify and categorize over 127 unique technologies.

---

## Installation & Usage

### 1. Start the Backend API (Python)

**Prerequisites:** Python 3.10+

```bash
# Navigate to the backend directory
cd backend

# Install dependencies
pip install -r requirements.txt
pip install fastapi uvicorn

# Run the API server
python api.py
```

### 2. Start the Frontend UI (Flutter)

**Prerequisites:** Flutter SDK installed

```bash
# Navigate to the frontend directory
cd frontend

# Get dependencies
flutter pub get

# Run the application (Chrome or Desktop)
flutter run -d chrome
```

---

## Output Format

Each domain produces a JSON entry like:

```json
{
   "domain": "example.com",
   "technologies": [
      {
         "name": "Shopify",
         "confidence": 100,
         "evidence": "header: X-ShopId present"
      },
      {
         "name": "Google Analytics",
         "confidence": 90,
         "evidence": "script src: google-analytics.com/analytics.js"
      }
   ]
}
```

---

## Tech Stack

- **Python 3.10 + FastAPI** — async backend API
- **Flutter (Dart)** — cross-platform frontend dashboard
- **requests / httpx** — HTTP fetching
- **BeautifulSoup4** — HTML parsing
- **dnspython** — DNS record analysis
- **Wappalyzer signatures** — technology fingerprint database

---

## 🧠 Architecture & Scaling

### 1. Main Issues & How I'd Fix Them

**Blocking I/O & Timeouts**

The current implementation uses the synchronous `requests` library. A single slow or unresponsive website (30s timeout) blocks the entire worker thread, killing throughput.

*Fix:* Rewrite I/O using Python's `asyncio` with `aiohttp` or `httpx`. Pair this with a semaphore (e.g., max 50 concurrent connections) to prevent overwhelming target servers. This alone could improve throughput 20–50x.

**Bot Protection (WAFs & Cloudflare)**

Many production websites block automated HTTP requests — especially those behind Cloudflare or AWS WAF. Static header-based detection misses technologies that are only revealed after JavaScript execution.

*Fix:* Implement rotating residential proxies and randomised User-Agent strings for standard requests. For the subset of domains requiring JS rendering, integrate **Playwright** in headless mode. This adds latency but recovers technology signals that are invisible in raw HTML.

---

### 2. Scaling to Millions of Domains

Crawling 10M domains in 30 days = ~4 domains/second, continuously. The current single-process design cannot achieve this. Here's the distributed architecture I'd build:

- **Message Broker** — Push all domains into **Apache Kafka** or RabbitMQ. This decouples ingestion from processing and allows workers to scale independently. Kafka also provides replay capability if a worker batch fails.
- **Distributed Workers** — Deploy worker pods using **Celery + Python**, containerised in Docker and orchestrated by **Kubernetes**. Each worker pulls a domain, runs the async scan pipeline, and writes the result. Auto-scaling based on queue depth handles burst loads.
- **Storage Layer** — Raw results → **MongoDB** (fast writes, schema-flexible JSON). Processed data → **Google BigQuery** or Snowflake. The sales team can then run queries like: *"find all domains using Shopify but not Klaviyo"* in seconds.
- **Caching & Deduplication** — A **Redis bloom filter** prevents re-crawling recently-seen domains. HTTP-level caching (`ETag` / `If-Modified-Since`) reduces redundant requests on repeat scans.

---

### 3. Error Handling & Resilience

At scale, failures are inevitable — pages time out, proxies die, servers return 503s. A 0.1% error rate across 10M domains means 10,000 broken records if unhandled.

- **Retry with exponential backoff** — Transient errors (503, timeout) should be retried with increasing delays (1s → 2s → 4s). Permanent errors (404, parsing failure) should be logged and skipped immediately — retrying them wastes time and risks bans.
- **Failed URL queue** — Every failed domain gets written to a dedicated queue or file with the reason for failure. After the main run, these can be reprocessed with a different proxy or longer timeout — not blindly retried with the same parameters.
- **Validate responses, not just status codes** — A 200 OK can still be a CAPTCHA page or a login redirect. The scraper should verify that the response actually contains expected content before saving it.

---

### 4. Storage Strategy

- **Two-layer storage** — Raw HTML/JSON is stored separately from processed, structured data. This means if parsing logic changes or a bug is found, pages can be reprocessed without re-crawling — saving bandwidth and avoiding re-triggering bot protection.
- **Incremental writes** — Data is processed and written per domain, not accumulated in memory. This keeps memory usage flat and allows the job to resume from where it left off after a crash.
- **Batch inserts** — Instead of writing one row at a time, results are buffered and written in batches (e.g., 100–1000 records), reducing I/O pressure significantly at scale.

---

### 5. Discovering New Technologies

- **Wappalyzer Sync** — A weekly cron job pulls the latest `technologies.json` from the open-source Wappalyzer GitHub repo and merges it into the local signature database. Zero manual effort for most updates.
- **ML-based Anomaly Detection** — Cluster unknown HTTP headers, recurring JS globals, and unmapped cookies across thousands of domains. When an unknown pattern appears in >0.1% of sites, flag it for a human engineer to label. This catches emerging frameworks before they appear in curated databases.
- **Community Signal Monitoring** — Monitor **ProductHunt**, **GitHub Trending**, and **Hacker News** for new dev tools. Write detection rules proactively as frameworks gain traction — before mass adoption.
- **Competitive Intelligence** — Periodically scan the websites of known technology vendors themselves to extract self-identifying patterns (meta tags, JS variables, DNS entries). Vendors often announce their own presence unambiguously.

---

*Built as part of a technical challenge. All findings and code are available in this repository.*