import json
import time
import pandas as pd
from fetcher import fetch_domain
from detector import load_wappalyzer, detect_technologies
from dns_resolver import detect_dns_technologies


def load_domains(filepath):
    if filepath.endswith(".parquet"):
        df = pd.read_parquet(filepath)
        return df["root_domain"].tolist()
    with open(filepath) as f:
        return [line.strip() for line in f if line.strip()]


def fetch_all(domains):
    results = {}
    success = 0
    failed = 0

    for i, domain in enumerate(domains, 1):
        result = fetch_domain(domain)

        if result["error"]:
            print(f"  [{i}/{len(domains)}] FAIL  {domain} — {result['error']}")
            failed += 1
        else:
            print(f"  [{i}/{len(domains)}] OK    {domain} — {result['status']}, {len(result['html'])} bytes")
            success += 1

        results[domain] = result

    with open("data/fetched.json", "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"\nFetch done: {success} ok, {failed} failed")
    return results


def analyze_all(fetched, domains):
    categories, technologies = load_wappalyzer()
    print(f"Wappalyzer DB: {len(technologies)} technologies loaded")

    results = {}
    for i, (domain, data) in enumerate(fetched.items(), 1):
        if data.get("error"):
            results[domain] = {"error": data["error"], "technologies": {}}
            continue

        techs = detect_technologies(data, technologies, categories)

        # DNS lookups
        dns_techs = detect_dns_technologies(domain)
        for tech_name, tech_info in dns_techs.items():
            if tech_name not in techs:
                techs[tech_name] = tech_info

        results[domain] = {"technologies": techs}
        print(f"  [{i}/{len(fetched)}] {domain} — {len(techs)} technologies")

    return results


def save_results(results, json_path="output/results.json", csv_path="output/results.csv"):
    import os
    import csv

    os.makedirs("output", exist_ok=True)

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["domain", "technology", "categories", "evidence"])
        for domain, data in results.items():
            for tech_name, tech_info in data.get("technologies", {}).items():
                writer.writerow([
                    domain,
                    tech_name,
                    "; ".join(tech_info.get("categories", [])),
                    " | ".join(tech_info.get("evidence", [])),
                ])

    total_techs = sum(len(d.get("technologies", {})) for d in results.values())
    unique_techs = set()
    for d in results.values():
        unique_techs.update(d.get("technologies", {}).keys())

    print(f"\nResults saved to {json_path} and {csv_path}")
    print(f"Total detections: {total_techs}")
    print(f"Unique technologies: {len(unique_techs)}")


def main():
    domains = load_domains("data/domains.parquet")
    print(f"Domains: {len(domains)}")
    start = time.time()

    # Step 1: Fetch (or load cached)
    import os
    if os.path.exists("data/fetched.json"):
        print("Loading cached fetch data...")
        with open("data/fetched.json") as f:
            fetched = json.load(f)
    else:
        print("Fetching domains...")
        fetched = fetch_all(domains)

    # Step 2: Detect technologies (HTTP + DNS)
    print("\nAnalyzing technologies...")
    results = analyze_all(fetched, domains)

    # Step 3: Save results
    save_results(results)

    print(f"\nTotal time: {time.time() - start:.0f}s")


if __name__ == "__main__":
    main()