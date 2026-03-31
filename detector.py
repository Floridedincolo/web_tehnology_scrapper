import json
import re


def load_wappalyzer(filepath="data/wappalyzer.json"):
    with open(filepath) as f:
        data = json.load(f)
    return data["categories"], data["technologies"]


def make_regex(pattern):
    if not pattern or pattern == "":
        return None
    pattern = pattern.split("\\;")[0]
    try:
        return re.compile(pattern, re.IGNORECASE)
    except re.error:
        return None


def detect_technologies(fetch_result, technologies, categories):
    html = fetch_result.get("html", "")
    headers = fetch_result.get("headers", {})
    cookies = fetch_result.get("cookies", [])

    headers_lower = {k.lower(): v for k, v in headers.items()}

    script_srcs = re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', html, re.IGNORECASE)

    meta_tags = {}
    for match in re.finditer(r'<meta[^>]+name=["\']([^"\']+)["\'][^>]+content=["\']([^"\']+)["\']', html, re.IGNORECASE):
        meta_tags[match.group(1).lower()] = match.group(2)
    for match in re.finditer(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']([^"\']+)["\']', html, re.IGNORECASE):
        meta_tags[match.group(2).lower()] = match.group(1)

    detected = {}

    for tech_name, tech_data in technologies.items():
        if not isinstance(tech_data, dict):
            continue

        evidence = []

        # HTML patterns
        html_patterns = tech_data.get("html", [])
        if isinstance(html_patterns, str):
            html_patterns = [html_patterns]
        for pattern in html_patterns:
            regex = make_regex(pattern)
            if regex and regex.search(html):
                evidence.append(f"html: {pattern[:60]}")

        # Header patterns
        for header_name, header_pattern in tech_data.get("headers", {}).items():
            header_val = headers_lower.get(header_name.lower(), "")
            if not header_val:
                continue
            if header_pattern == "":
                evidence.append(f"header: {header_name}")
            else:
                regex = make_regex(header_pattern)
                if regex and regex.search(header_val):
                    evidence.append(f"header: {header_name}={header_val[:40]}")

        # Cookie patterns
        for cookie_name, cookie_pattern in tech_data.get("cookies", {}).items():
            for cookie in cookies:
                if cookie.lower() == cookie_name.lower():
                    evidence.append(f"cookie: {cookie}")

        # Script patterns
        script_patterns = tech_data.get("scripts", [])
        if isinstance(script_patterns, str):
            script_patterns = [script_patterns]
        for pattern in script_patterns:
            regex = make_regex(pattern)
            if regex:
                for src in script_srcs:
                    if regex.search(src):
                        evidence.append(f"script: {src[:60]}")
                        break

        # Meta tag patterns
        for meta_name, meta_pattern in tech_data.get("meta", {}).items():
            meta_val = meta_tags.get(meta_name.lower(), "")
            if not meta_val:
                continue
            if meta_pattern == "":
                evidence.append(f"meta: {meta_name}")
            else:
                regex = make_regex(meta_pattern)
                if regex and regex.search(meta_val):
                    evidence.append(f"meta: {meta_name}={meta_val[:40]}")

        if evidence:
            cat_ids = tech_data.get("cats", [])
            cat_names = []
            for cid in cat_ids:
                cat_info = categories.get(str(cid), {})
                if isinstance(cat_info, dict):
                    cat_names.append(cat_info.get("name", "Unknown"))

            detected[tech_name] = {
                "categories": cat_names,
                "evidence": evidence,
                "website": tech_data.get("website", ""),
            }

    # Resolve implies
    to_add = {}
    for tech_name, info in detected.items():
        tech_data = technologies.get(tech_name, {})
        if not isinstance(tech_data, dict):
            continue
        implies = tech_data.get("implies", [])
        if isinstance(implies, str):
            implies = [implies]
        for implied in implies:
            implied_clean = implied.split("\\;")[0].strip()
            if implied_clean and implied_clean not in detected and implied_clean not in to_add:
                impl_data = technologies.get(implied_clean, {})
                cat_ids = impl_data.get("cats", []) if isinstance(impl_data, dict) else []
                cat_names = []
                for cid in cat_ids:
                    cat_info = categories.get(str(cid), {})
                    if isinstance(cat_info, dict):
                        cat_names.append(cat_info.get("name", "Unknown"))
                to_add[implied_clean] = {
                    "categories": cat_names,
                    "evidence": [f"implied by {tech_name}"],
                    "website": impl_data.get("website", "") if isinstance(impl_data, dict) else "",
                }

    detected.update(to_add)
    return detected