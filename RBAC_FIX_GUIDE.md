# Shimmy RBAC/Istio Fix Guide

## Problem Analysis

### Issue
- `/v1/models` endpoint works ✅
- `/health` and `/api/generate` return **RBAC: access denied** ❌

### Root Cause
SAP AI Core uses **Istio service mesh** with strict RBAC policies. By default, KServe only allows specific paths:
- `/v1/*` paths (OpenAI-compatible)
- Standard health check paths

Custom paths like `/health` and `/api/*` are blocked by Istio's AuthorizationPolicy.

## Solution Components

### 1. Dockerfile.rbac-fix
**Location**: `infrastructure/docker/images/shimmy-server/Dockerfile.rbac-fix`

**Changes from Dockerfile.simple**:
- Same base configuration
- Ensures proper signal handling with exec form CMD
- Binds to `0.0.0.0:8080` for KServe compatibility

**Build**:
```bash
cd infrastructure/docker/images/shimmy-server
docker build --platform linux/amd64 -f Dockerfile.rbac-fix \
  -t docker.io/gjkarthik/shimmy:rbac-fix .
docker push docker.io/gjkarthik/shimmy:rbac-fix
```

### 2. shimmy-serving-template-rbac-fix.yaml
**Location**: `infrastructure/docker/images/shimmy-server/shimmy-serving-template-rbac-fix.yaml`

**Key Features**:

#### A. Istio Configuration
```yaml
metadata:
  annotations: |
    sidecar.istio.io/inject: "true"
    proxy.istio.io/config: |
      holdApplicationUntilProxyStarts: true
  labels: |
    sidecar.istio.io/inject: "true"
```

#### B. Port Configuration
```yaml
ports:
- containerPort: 8080
  protocol: TCP
  name: http1  # Required for Istio HTTP routing
```

#### C. AuthorizationPolicy (Critical!)
```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: shimmy-rbac-fix-allow-all
spec:
  selector:
    matchLabels:
      scenarios.ai.sap.com/id: "shimmy-rbac-fix"
  action: ALLOW
  rules:
  - to:
    - operation:
        paths:
        - "/v1/*"      # OpenAI compatible paths
        - "/api/*"     # Shimmy API paths
        - "/health"    # Custom health endpoint
        - "/healthz"   # Kubernetes health
        - "/ready"     # Readiness endpoint
        - "/metrics"   # Prometheus metrics
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
```

## Deployment Steps

### Step 1: Build and Push Image
```bash
cd infrastructure/docker/images/shimmy-server

# Build for AMD64 (SAP AI Core)
docker build --platform linux/amd64 \
  -f Dockerfile.rbac-fix \
  -t docker.io/gjkarthik/shimmy:rbac-fix .

# Push to registry
docker push docker.io/gjkarthik/shimmy:rbac-fix
```

### Step 2: Deploy ServingTemplate
```bash
kubectl apply -f shimmy-serving-template-rbac-fix.yaml
```

### Step 3: Create Deployment
Use SAP AI Core UI or API to create a deployment using the `shimmy-rbac-fix` scenario.

### Step 4: Verify AuthorizationPolicy
```bash
# Check if AuthorizationPolicy was created
kubectl get authorizationpolicy -n <your-namespace>

# Should see:
# NAME                        AGE
# shimmy-rbac-fix-allow-all   1m
```

### Step 5: Test Endpoints
```bash
# Get inference service URL
INFERENCE_URL=$(kubectl get inferenceservice -n <namespace> -o jsonpath='{.items[0].status.url}')

# Test /v1/models
curl $INFERENCE_URL/v1/models

# Test /health (should now work!)
curl $INFERENCE_URL/health

# Test /api/generate (should now work!)
curl -X POST $INFERENCE_URL/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model": "phi3-mini", "prompt": "Hello"}'
```

## Troubleshooting

### Still Getting RBAC Errors?

#### 1. Check AuthorizationPolicy Exists
```bash
kubectl get authorizationpolicy shimmy-rbac-fix-allow-all -n <namespace>
```

If missing, apply it separately:
```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: shimmy-rbac-fix-allow-all
  namespace: <your-namespace>
spec:
  selector:
    matchLabels:
      scenarios.ai.sap.com/id: "shimmy-rbac-fix"
  action: ALLOW
  rules:
  - to:
    - operation:
        paths: ["/v1/*", "/api/*", "/health", "/healthz", "/ready", "/metrics"]
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
EOF
```

#### 2. Check Pod Labels
```bash
kubectl get pod -n <namespace> -l scenarios.ai.sap.com/id=shimmy-rbac-fix --show-labels
```

Ensure the label `scenarios.ai.sap.com/id: shimmy-rbac-fix` is present.

#### 3. Check Istio Injection
```bash
kubectl get pod -n <namespace> -o jsonpath='{.items[0].spec.containers[*].name}'
```

Should show: `kserve-container istio-proxy`

#### 4. View Istio Logs
```bash
kubectl logs -n <namespace> <pod-name> -c istio-proxy
```

Look for RBAC denials in the Envoy logs.

#### 5. Namespace-Wide Policy
If the AuthorizationPolicy doesn't work, try a namespace-wide policy:
```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-all-shimmy
  namespace: <your-namespace>
spec:
  action: ALLOW
  rules:
  - to:
    - operation:
        paths: ["/*"]
        methods: ["*"]
EOF
```

## Comparison: Working vs Fixed Versions

| Feature | Dockerfile.simple | Dockerfile.rbac-fix |
|---------|------------------|-------------------|
| Base Image | Debian Bookworm | Debian Bookworm |
| Shimmy Install | cargo install | cargo install |
| User | shimmy (1000) | shimmy (1000) |
| Port | 8080 | 8080 |
| Bind Address | 0.0.0.0:8080 | 0.0.0.0:8080 |
| CMD Format | exec form | exec form |
| **Difference** | None | **Identical!** |

| Feature | v2.yaml (Working) | rbac-fix.yaml (RBAC Fixed) |
|---------|------------------|---------------------------|
| Image | shimmy:latest | shimmy:rbac-fix |
| Health Probes | TCP only | HTTP /v1/models |
| Port Name | none | **http1** ✅ |
| Istio Injection | implicit | **explicit** ✅ |
| **AuthorizationPolicy** | ❌ Missing | **✅ Included** |
| Allowed Paths | default | **/v1/\*, /api/\*, /health** ✅ |

## Key Takeaways

1. **AuthorizationPolicy is mandatory** for custom API paths in SAP AI Core
2. **Port must be named** (`http1`) for Istio HTTP routing
3. **Explicit Istio injection** ensures consistent behavior
4. **Paths must be whitelisted** in AuthorizationPolicy
5. **The Dockerfile doesn't need changes** - it's a Kubernetes/Istio config issue

## Testing Checklist

- [ ] `/v1/models` returns model list
- [ ] `/health` returns OK (not RBAC error)
- [ ] `/api/generate` accepts POST requests
- [ ] AuthorizationPolicy exists in namespace
- [ ] Pod has `istio-proxy` sidecar
- [ ] Pod labels match AuthorizationPolicy selector

## Success Criteria

All endpoints should return HTTP 200 (or appropriate status), **not RBAC: access denied**.
