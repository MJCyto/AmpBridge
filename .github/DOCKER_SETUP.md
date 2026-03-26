# Docker Hub Setup for GitHub Actions

This repository uses GitHub Actions to automatically build and push multi-architecture Docker images to Docker Hub.

## Required Secrets

You need to add the following secrets to your GitHub repository:

### 1. DOCKERHUB_USERNAME
- Your Docker Hub username
- Go to: Repository Settings → Secrets and variables → Actions → New repository secret
- Name: `DOCKERHUB_USERNAME`
- Value: Your Docker Hub username (e.g., `cytotoxicdingus`)

### 2. DOCKERHUB_TOKEN
- Your Docker Hub access token
- Go to: [Docker Hub Account Settings](https://hub.docker.com/settings/security) → New Access Token
- Name: `github-actions` (or any name you prefer)
- Permissions: Read, Write, Delete
- Copy the token and add it as a repository secret
- Name: `DOCKERHUB_TOKEN`
- Value: The access token you generated

### 3. SECRET_KEY_BASE (Optional)
- A secret key for the Phoenix application
- Generate one with: `mix phx.gen.secret`
- Go to: Repository Settings → Secrets and variables → Actions → New repository secret
- Name: `SECRET_KEY_BASE`
- Value: The generated secret key

## Workflow Triggers

The workflow will run when:
- Code is pushed to the `master` or `main` branch
- A pull request is merged into `master` or `main`
- Manually triggered via GitHub Actions UI

## Image Tags

The workflow creates the following tags:
- `latest` - Latest stable version (master branch only)
- `beta` - Beta version (master branch only)
- `{branch-name}` - Branch-specific tags
- `{branch-name}-{commit-sha}` - Specific commit tags

## Multi-Architecture Support

The workflow builds for:
- `linux/amd64` - Intel/AMD 64-bit
- `linux/arm64` - ARM 64-bit (Apple Silicon, newer ARM servers)
- `linux/arm/v7` - ARM 32-bit v7 (Raspberry Pi 3/4)

## Manual Build

You can manually trigger a build:
1. Go to the Actions tab in your GitHub repository
2. Select "Build and Push Multi-Arch Docker Image (Advanced)"
3. Click "Run workflow"
4. Optionally specify a custom tag

## Troubleshooting

### Build Failures
- Check the Actions tab for detailed logs
- Ensure all secrets are properly configured
- Verify Docker Hub permissions

### SSL Issues with ARM Builds
- The workflow uses GitHub's native runners which have better ARM support
- If issues persist, the workflow will still build AMD64 successfully

### Cache Issues
- The workflow uses GitHub Actions cache for faster builds
- If you encounter cache issues, you can disable caching in the workflow file
