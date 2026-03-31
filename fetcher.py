import requests
import urllib3
import re

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}


def extract_cookies_from_headers(headers):
    cookies = []
    for key, value in headers.items():
        if key.lower() == "set-cookie":
            match = re.match(r"([^=]+)=", value)
            if match:
                cookies.append(match.group(1).strip())
    return cookies


def fetch_robots_txt(domain, timeout=10):
    for scheme in ["https", "http"]:
        try:
            resp = requests.get(
                f"{scheme}://{domain}/robots.txt",
                timeout=timeout, headers=HEADERS,
                allow_redirects=True, verify=False,
            )
            if resp.status_code == 200 and "user-agent" in resp.text.lower():
                return resp.text
        except Exception:
            continue
    return ""


def fetch_domain(domain, timeout=15):
    last_error = None

    for scheme in ["https", "http"]:
        url = f"{scheme}://{domain}"
        try:
            resp = requests.get(
                url, timeout=timeout, headers=HEADERS,
                allow_redirects=True, verify=False,
            )

            cookie_names = [c.name for c in resp.cookies]
            header_cookies = extract_cookies_from_headers(resp.headers)
            all_cookies = list(set(cookie_names + header_cookies))

            robots = fetch_robots_txt(domain)

            return {
                "url": str(resp.url),
                "status": resp.status_code,
                "html": resp.text,
                "headers": dict(resp.headers),
                "cookies": all_cookies,
                "robots_txt": robots,
                "error": None,
            }
        except requests.exceptions.Timeout:
            last_error = f"Timeout after {timeout}s"
        except requests.exceptions.ConnectionError:
            last_error = "Connection failed"
        except Exception as e:
            last_error = str(e)[:100]

    return {
        "url": f"https://{domain}",
        "status": 0, "html": "", "headers": {},
        "cookies": [], "robots_txt": "",
        "error": last_error,
    }