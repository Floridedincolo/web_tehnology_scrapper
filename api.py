from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Any
from fastapi import FastAPI, UploadFile, File
import pandas as pd
import io

from fetcher import fetch_domain, fetch_robots_txt
from detector import load_wappalyzer, detect_technologies
from dns_resolver import detect_dns_technologies

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ScanRequest(BaseModel):
    domains: List[str]

@app.post("/upload-parquet")
async def upload_parquet(file: UploadFile = File(...)):
    contents = await file.read()
    try:
        df = pd.read_parquet(io.BytesIO(contents))
        if 'root_domain' in df.columns:
            domains = df['root_domain'].dropna().astype(str).tolist()
        else:
            # Fallback if other column name is used, take the first column
            domains = df.iloc[:, 0].dropna().astype(str).tolist()
        return {"domains": domains[:1000]} # Limit to 1000 to prevent crashing the UI/backend
    except Exception as e:
        return {"error": str(e)}

@app.post("/scan")
def scan_domains(request: ScanRequest) -> Dict[str, Any]:
    categories, technologies = load_wappalyzer()

    results = {}
    for domain in request.domains:
        # Fetch data
        data = fetch_domain(domain)

        if data.get("error"):
            results[domain] = {"error": data["error"], "technologies": {}}
            continue

        # Enrich with robots.txt
        if not data.get("robots_txt"):
            robots = fetch_robots_txt(domain)
            if robots:
                data["robots_txt"] = robots

        # Detect tech from HTTP/HTML
        techs = detect_technologies(data, technologies, categories)

        # Detect tech from DNS
        dns_techs = detect_dns_technologies(domain)
        for tech_name, tech_info in dns_techs.items():
            if tech_name not in techs:
                techs[tech_name] = tech_info

        results[domain] = {"technologies": techs}

    return results
