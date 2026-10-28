#!/usr/bin/env python3
"""HOTICE static public-site CI checks with only the Python stdlib."""
from html.parser import HTMLParser
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "web" / "public"

class AssetScanner(HTMLParser):
    def __init__(self):
        super().__init__()
        self.assets = set()
        self.external_sources = []
        self.element_ids = set()
        self.external_scripts = []

    def handle_starttag(self, tag, attrs):
        props = dict(attrs)
        if props.get("id"):
            if props["id"] in self.element_ids:
                raise ValueError("duplicate element ID " + props["id"])
            self.element_ids.add(props["id"])
        if tag == "script" and props.get("src", "").startswith(("http:", "https:")):
            self.external_scripts.append(props["src"])
        if tag in ("script", "link") and (props.get("src") or props.get("href")):
            link = props.get("src") or props.get("href")
            if link.startswith("assets/"):
                self.assets.add(link)
        if tag in ("video", "iframe", "source") and props.get("src", "").startswith(("http:", "https:")):
            self.external_sources.append(props["src"])


def main():
    html = (PUBLIC / "index.html").read_text(encoding="utf-8")
    scanner = AssetScanner()
    scanner.feed(html)
    for path in scanner.assets:
        assert (PUBLIC / path).is_file(), "Missing static asset: " + path
    assert not scanner.external_scripts, "External scripts may expose local data"
    assert not scanner.external_sources, "External media requires rights clearance"
    assert "What's Possible with HOTICE" in html
    assert "Use this prompt" not in html or "libraryCards" in html
    assert "admin.php" not in html, "Do not link to an unimplemented admin"
    assert "youtube.com/watch" not in html, "No uncleared external example embeds"
    assert 'name="hotice-api-origin"' in html, "Configure the shared HTTPS API origin at deployment"
    for element_id in ("accountLogin", "accountEmail", "accountPassword", "accountStatus", "accountSignOut"):
        assert 'id="' + element_id + '"' in html, "Missing shared-account workflow control: " + element_id
    for element_id in ("projectTitle", "saveLocalProject", "localProjects", "cloudSyncConsent",
                       "loadCloudProjects", "cloudProjects", "cloudProjectStatus"):
        assert 'id="' + element_id + '"' in html, "Missing local/cloud project control: " + element_id
    assert 'type="checkbox"' in html and "I agree to sync the saved project I choose" in html

    raw = json.loads((PUBLIC / "assets" / "inspiration.json").read_text(encoding="utf-8"))
    assert raw["schemaVersion"] == 1
    ids = set()
    valid_models = {
        "cinematic_demo", "character_demo",
        "storyboard_demo", "multimodal_demo",
    }
    for entry in raw["templates"]:
        assert entry["id"] not in ids, "Duplicate template ID"
        ids.add(entry["id"])
        assert entry["origin"] == "hotice_original", "External template requires approval"
        assert entry["publicationStatus"] == "approved"
        assert entry["modelId"] in valid_models
        assert entry["promptStatus"] == "editorial_original"
        assert entry["previewUrl"] is None, "External videos must be rights-cleared first"
        provenance = entry["provenance"]
        assert provenance["creator"]
        assert provenance["promptOrigin"]
        assert provenance["promptLicense"]
        assert provenance["licenseEvidence"]
        assert provenance["attributionRequired"] is True
        assert provenance["attributionText"]
        assert provenance["mediaLicense"] is None
        assert provenance["embedAllowed"] is False
        assert provenance["lastVerified"]
        assert provenance["sourceUrl"] is None
        assert len(entry["prompt"]) >= 20
        assert len(set(entry["actorSlots"])) == len(entry["actorSlots"])
        for role in entry["actorSlots"]:
            assert re.fullmatch(r"Actor[0-9]+", role)
            assert "{{" + role + "}}" in entry["prompt"]
    assert len(ids) >= 5, "Catalog needs a meaningful collection"
    assert "actorNameInput" in html and "actorAssignments" in html
    script = (PUBLIC / "assets" / "site.js").read_text(encoding="utf-8")
    assert "accountApi('/v1/auth/login'" in script and "accountApi('/v1/me'" in script
    assert "accountApi('/v1/auth/logout'" in script
    assert "credentials: 'omit'" in script and "redirect: 'error'" in script
    assert "parsed.protocol === 'http:' && localPage" in script, "Insecure API origins must be limited to local development"
    assert "localStorage.setItem('hotice.accessToken'" not in script
    assert "sessionStorage.setItem('hotice.accessToken'" not in script
    assert "indexedDB.open(projectDbName, 1)" in script, "Browser projects must persist locally"
    assert "accountApi('/v1/projects'" in script, "Cloud listing must use the shared project API"
    assert "method: 'PUT', token: accountToken, body" in script, "Cloud writes must be authenticated"
    assert "projectConsent?.checked" in script, "Cloud actions must require explicit consent"
    assert "Upload as separate cloud copy" in script, "Revision conflicts must keep local work recoverable"
    assert "'/v1/projects/' + encodeURIComponent(id)" in script
    assert "actorStorageKey" in script
    assert "Assign your Actors to this prompt" in script
    assert "prompt.replaceAll('{{' + role + '}}', actors[index])" in script
    apache = (PUBLIC / ".htaccess").read_text(encoding="utf-8")
    connect_src = re.search(r"(?:^|;)\\s*connect-src\\s+([^;]+)", apache)
    assert connect_src, "CSP must define connect-src"
    assert connect_src.group(1).split() == ["'self'", "https://api.your-hotice-domain.example"], \
        "CSP must allow only same-origin and the exact configured API host"
    print(f"HOTICE static web verification successful: {len(ids)} templates, "
          f"{len(scanner.assets)} assets, no uncleared remote media.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("WEB CHECK FAILED:", str(exc), file=sys.stderr)
        raise

