# GitHub Actions GPU Build Setup & Usage

## Overview

This guide explains how to build GPU-enabled Shimmy images using GitHub Actions, since building CUDA applications requires a Linux environment with CUDA toolkit.

## Prerequisites

1. **GitHub Repository**: Your code must be in a GitHub repository
2. **Docker Hub Account**: `gjkarthik` account with push access
3. **Docker Hub Token**: Personal access token for authentication

## Step 1: Add Docker Hub Token to GitHub Secrets

1. **Create Docker Hub Token** (if you don't have one):
   - Go to https://hub.docker.com/settings/security
   - Click "New Access Token"
   - Name: `github-actions-shimmy-gpu`
   - Permissions: Read & Write
   - Copy the token (you won't see it again!)

2. **Add Secret to GitHub**:
   - Go to your GitHub repository: `https://github.com/plturrell/aModels`
   - Click **Settings** → **Secrets and variables** → **Actions**
   - Click **New repository secret**
   - Name: `DOCKERHUB_TOKEN`
   - Value: Paste your Docker Hub token
   - Click **Add secret**

## Step 2: Commit and Push the Workflow

The workflow file is already created at `.github/workflows/build-shimmy-gpu.yml`.

```bash
# From your local machine
cd /Users/karthikeyan/git/aModels

# Stage the workflow file
git add .github/workflows/build-shimmy-gpu.yml

# Also stage the Dockerfiles and scripts
git add infrastructure/docker/images/shimmy-server/Dockerfile.gpu-nvidia-base
git add infrastructure/docker/images/shimmy-server/start-with-downloader-gpu.sh
git add infrastructure/docker/images/shimmy-server/model-downloader-proxy.py
git add infrastructure/docker/images/shimmy-server/shimmy-serving-template-gpu.yaml

# Commit
git commit -m "Add GitHub Actions workflow for GPU-enabled Shimmy build"

# Push to GitHub
git push origin main
```

## Step 3: Trigger the Build

### Option A: Manual Trigger (Recommended for First Build)

1. Go to your repository on GitHub
2. Click **Actions** tab
3. Click **Build Shimmy GPU Image** workflow (left sidebar)
4. Click **Run workflow** (right side)
5. Enter tag name (or use default `v2.7-gpu`)
6. Click **Run workflow** button

### Option B: Automatic Trigger

The workflow automatically runs when you push changes to:
- `Dockerfile.gpu-nvidia-base`
- `start-with-downloader-gpu.sh`
- `model-downloader-proxy.py`
- The workflow file itself

## Step 4: Monitor the Build

1. Click on the running workflow
2. Watch the build progress (takes ~15-20 minutes)
3. Key steps to watch:
   - ✅ Install CUDA Toolkit
   - ✅ Build and push GPU image (longest step)
   - ✅ Image digest

## Step 5: Verify the Image

Once complete, verify the image was pushed:

```bash
# Check Docker Hub
docker pull docker.io/gjkarthik/shimmy:v2.7-gpu

# Or check via Docker Hub website
# https://hub.docker.com/r/gjkarthik/shimmy/tags
```

## Build Output

The workflow produces:
- **Image**: `docker.io/gjkarthik/shimmy:v2.7-gpu` (or your specified tag)
- **Summary**: Available in the workflow run (GitHub Actions UI)
- **Features**:
  - CUDA 12.3.0 support
  - Built with `llama-cuda` feature flag
  - HuggingFace Hub integration
  - Dynamic model download proxy

## Troubleshooting

### Build Fails: "CUDA Toolkit not found"

**Unlikely** - The workflow installs CUDA toolkit explicitly. If this happens:
1. Check the "Install CUDA Toolkit" step logs
2. Verify Ubuntu 22.04 runner is being used

### Build Fails: "docker login failed"

Check your Docker Hub credentials:
1. Verify `DOCKERHUB_TOKEN` secret exists in GitHub
2. Verify the token is valid (not expired)
3. Verify username is `gjkarthik` in the workflow

### Build Takes Too Long (>30 minutes)

This is normal for first build. Subsequent builds use cache:
- First build: ~20-25 minutes (full Rust compilation)
- Cached builds: ~5-10 minutes

### Push Fails: "denied: requested access to the resource is denied"

Your Docker Hub token needs **Read & Write** permissions:
1. Create new token with correct permissions
2. Update `DOCKERHUB_TOKEN` secret in GitHub

## Next Steps After Successful Build

1. **Update Deployment Template**:
   ```yaml
   # In shimmy-serving-template-gpu.yaml
   image: docker.io/gjkarthik/shimmy:v2.7-gpu
   ```

2. **Deploy to SAP AI Core**:
   ```bash
   # Deploy using the GPU template
   kubectl apply -f infrastructure/docker/images/shimmy-server/shimmy-serving-template-gpu.yaml
   ```

3. **Verify GPU Usage**:
   - Check pod logs for "CUDA device found"
   - Monitor inference times (should be 10x faster)

## Workflow Features

### Smart Caching
- Uses GitHub Actions cache
- Speeds up subsequent builds significantly
- Cache key based on Dockerfile content

### Flexible Tagging
- Manual trigger: Specify custom tag
- Auto trigger: Uses default `v2.7-gpu`
- Easy to version your images

### Build Summary
- Auto-generated summary in GitHub Actions
- Shows image tags and next steps
- Easy to share build results

## Cost & Usage

- **Free Tier**: 2,000 GitHub Actions minutes/month
- **This Build**: Uses ~20-25 minutes (first time)
- **Recommendation**: Use manual trigger to avoid unnecessary builds

## Why GitHub Actions?

✅ **Ubuntu runners** have proper Linux environment
✅ **CUDA toolkit** can be installed easily
✅ **Free** for public repositories
✅ **Automated** and reproducible
✅ **No local Linux machine** required

## Alternative: Build Locally on Linux

If you have Linux machine with Docker:

```bash
# SSH to Linux machine
ssh user@linux-machine

# Clone repo
git clone https://github.com/plturrell/aModels.git
cd aModels/infrastructure/docker/images/shimmy-server

# Build and push
docker build -f Dockerfile.gpu-nvidia-base \
  -t docker.io/gjkarthik/shimmy:v2.7-gpu \
  --push .
```

But **GitHub Actions is recommended** for:
- Reproducibility
- No local setup required
- Automatic builds on code changes
- Build logs available forever

## Support

If you encounter issues:
1. Check workflow logs in GitHub Actions
2. Review this documentation
3. Verify Docker Hub credentials
4. Ensure CUDA toolkit installation succeeded

**Remember**: The workflow is designed to work out-of-the-box on GitHub's Ubuntu runners with all necessary CUDA components!
