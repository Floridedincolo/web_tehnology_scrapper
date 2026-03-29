import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def fetch_domain(domain, timeout=15):
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        )
    }

    last_error = None

    for scheme in ["https", "http"]:
        url = f"{scheme}://{domain}"
        try:
            resp = requests.get(
                url,
                timeout=timeout,
                headers=headers,
                allow_redirects=True,
                verify=False,
            )
            return {
                "url": str(resp.url),
                "status": resp.status_code,
                "html": resp.text,
                "headers": dict(resp.headers),
                "cookies": [c.name for c in resp.cookies],
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
        "status": 0,
        "html": "",
        "headers": {},
        "cookies": [],
        "error": last_error,
    }
res=fetch_domain('shopify.com')
print(res)