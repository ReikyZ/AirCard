# ⚠️ MANUAL ACTION REQUIRED: Enable GitHub Pages

## Current Status

All files are ready and merged into the `main` branch:
- ✅ `/docs/privacy.html` - Privacy policy page
- ✅ `/docs/index.html` - Documentation landing page  
- ✅ `/docs/.nojekyll` - Jekyll config
- ✅ `gh-pages` branch - Alternative deployment option

## Why Manual Action is Needed

GitHub's API tokens (including GITHUB_TOKEN in Actions) lack the `pages: write` permission 
needed to programmatically enable GitHub Pages. This is a security feature requiring 
repository administrator access.

## How to Enable (Takes 2 minutes)

### Option 1: Use main branch /docs (Recommended)

1. Go to: **https://github.com/ReikyZ/AirCard/settings/pages**

2. Under "Build and deployment":
   - Source: **Deploy from a branch**
   - Branch: **main**
   - Folder: **/docs**

3. Click **Save**

4. Wait ~1 minute for deployment

5. Verify: https://reikyz.github.io/AirCard/privacy.html should return HTTP 200

### Option 2: Use gh-pages branch

1. Go to: **https://github.com/ReikyZ/AirCard/settings/pages**

2. Under "Build and deployment":
   - Source: **Deploy from a branch**
   - Branch: **gh-pages**
   - Folder: **/ (root)**

3. Click **Save**

Both options serve the same content at the same URL.

## Verification

```bash
curl -I https://reikyz.github.io/AirCard/privacy.html
# Should return: HTTP/2 200
```

## What Was Attempted

All programmatic methods were tried and failed due to permissions:
- ✗ `gh api repos/{owner}/{repo}/pages` (403)
- ✗ `curl -X POST .../pages` (403)
- ✗ GitHub Actions with `actions/configure-pages` (403)
- ✗ GitHub Actions with `enablement: true` (403)
- ✗ GraphQL mutations (403 / Not Found)
- ✗ Workflow dispatch triggers (403)

## Files Changed

**Merged PRs:**
- [#1](https://github.com/ReikyZ/AirCard/pull/1) - Privacy policy page
- [#2](https://github.com/ReikyZ/AirCard/pull/2) - Pages configuration files
- [#3](https://github.com/ReikyZ/AirCard/pull/3) - Deployment workflow (will activate after Pages enabled)
- [#4](https://github.com/ReikyZ/AirCard/pull/4) - Workflow cleanup

**Main branch commits:**
- `a35a40c` - Trigger Pages deployment workflow
- `b2e1541` - Add GitHub Pages setup instructions
- `57183ec` - Enable Pages automatically in workflow
- `7adcad7` - Add GitHub Pages deployment workflow
- Plus earlier commits with privacy policy and config files

**Additional branch:**
- `gh-pages` - Standalone Pages branch (alternative deployment source)

## Next Steps

1. Repository admin enables Pages via settings (link above)
2. GitHub builds and deploys (automatic, ~60 seconds)
3. Privacy policy becomes accessible at target URL
4. Task complete ✅

---

**For Mac App Store:** Once live, use this URL in your App Store Connect listing:
`https://reikyz.github.io/AirCard/privacy.html`
