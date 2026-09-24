# GitHub Pages Setup Instructions

GitHub Pages needs to be manually enabled for this repository by a repository administrator.

## Steps to Enable GitHub Pages:

1. Navigate to: https://github.com/ReikyZ/AirCard/settings/pages
2. Under "Build and deployment":
   - **Source**: Select "Deploy from a branch"  
   - **Branch**: Select `main`
   - **Folder**: Select `/docs`
3. Click **Save**
4. Wait a few moments for GitHub to process the configuration
5. Once enabled, the privacy policy will be accessible at:
   https://reikyz.github.io/AirCard/privacy.html

## Automated Deployment

Once Pages is manually enabled, the GitHub Actions workflow (`.github/workflows/deploy-pages.yml`) 
will automatically deploy updates to the docs folder whenever changes are pushed to the main branch.

## Why Manual Setup is Required

The GitHub Actions GITHUB_TOKEN does not have sufficient permissions to programmatically 
enable GitHub Pages on a repository. This is a security feature that requires repository 
admin access to configure.

## Verification

After enabling, verify the site is working by visiting:
- Main docs page: https://reikyz.github.io/AirCard/
- Privacy policy: https://reikyz.github.io/AirCard/privacy.html

Both should return HTTP 200 and display the expected content.
