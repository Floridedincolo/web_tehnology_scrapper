import subprocess


def resolve_dns(domain, timeout=5):
    records = {"cname": [], "mx": [], "txt": [], "ns": []}

    for rtype in ["CNAME", "MX", "TXT", "NS"]:
        try:
            result = subprocess.run(
                ["dig", "+short", rtype, domain],
                capture_output=True, text=True, timeout=timeout
            )
            if result.returncode == 0 and result.stdout.strip():
                lines = [l.strip().strip('"') for l in result.stdout.strip().split("\n") if l.strip()]
                records[rtype.lower()] = lines
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

    return records


DNS_SIGNATURES = [
    # CNAME / NS → hosting, CDN, CMS
    ("cloudflare", "Cloudflare"),
    ("netlify", "Netlify"),
    ("vercel", "Vercel"),
    ("herokuapp.com", "Heroku"),
    ("github.io", "GitHub Pages"),
    ("azurewebsites.net", "Microsoft Azure"),
    ("cloudfront.net", "Amazon CloudFront"),
    ("fastly.net", "Fastly"),
    ("wpengine.com", "WP Engine"),
    ("squarespace.com", "Squarespace"),
    ("myshopify.com", "Shopify"),
    ("shopify.com", "Shopify"),
    ("wixdns.net", "Wix"),
    ("webflow.com", "Webflow"),
    ("ghost.io", "Ghost"),
    ("amazonaws.com", "Amazon Web Services"),
    ("fly.dev", "Fly.io"),
    # MX → email provider
    ("google.com", "Google Workspace"),
    ("googlemail.com", "Google Workspace"),
    ("outlook.com", "Microsoft 365"),
    ("protection.outlook", "Microsoft 365"),
    ("pphosted.com", "Proofpoint"),
    ("mimecast.com", "Mimecast"),
    ("mailgun.org", "Mailgun"),
    ("sendgrid.net", "SendGrid"),
    ("secureserver.net", "GoDaddy Email"),
    ("zoho.com", "Zoho Mail"),
    ("ovh.net", "OVH"),
    # TXT → verification, security
    ("google-site-verification", "Google Search Console"),
    ("facebook-domain-verification", "Facebook Domain Verification"),
    ("v=spf1", "SPF"),
    ("hubspot", "HubSpot"),
    ("atlassian-domain-verification", "Atlassian"),
    ("docusign", "DocuSign"),
    ("apple-domain-verification", "Apple"),
    ("ms=", "Microsoft 365"),
]


def detect_dns_technologies(domain, timeout=5):
    records = resolve_dns(domain, timeout)
    all_values = " ".join(
        records["cname"] + records["mx"] + records["txt"] + records["ns"]
    ).lower()

    detected = {}
    for pattern, tech_name in DNS_SIGNATURES:
        if pattern in all_values:
            detected[tech_name] = {
                "categories": ["DNS"],
                "evidence": [f"DNS record contains '{pattern}'"],
            }

    return detected