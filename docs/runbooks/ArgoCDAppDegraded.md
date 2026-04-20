# ArgoCDAppDegraded

**Severity:** warning · **For:** 15m

## What fired

ArgoCD Application `$labels.name` has health `Degraded` for 15+ min.

## Impact

Usually cosmetic if services themselves are running; sometimes signals a real resource in failed state. ArgoCD uses `resourceHealthSource: appTree` so any failed sub-resource (Pod, Job, ReplicaSet) propagates up.

## First steps

Open ArgoCD UI (cd.pmon.dev) → app → resource tree → find red item.

CLI alternative:

```bash
kubectl -n $NS get pods,jobs | awk '$3!="Running" && $3!="Completed"'
kubectl -n argocd get application $APP -o yaml | grep -A5 health
```

## Common causes

| Red child | Fix |
|---|---|
| Failed Job (e.g. Kopia, setup) | `kubectl -n $NS delete job $JOB` — ArgoCD re-creates next sync |
| Pod in Error | Force-delete; new pod comes up |
| ReplicaSet unavailable | Check ResourceQuota, image pull error, CrashLoopBackOff |
| Stale hook Job w/ finalizer | Strip finalizer + delete |

## Fix

Remove the red item. Hard-refresh app:

```bash
kubectl -n argocd annotate application $APP argocd.argoproj.io/refresh=hard --overwrite
```

If timestamp doesn't update after refresh, restart argocd-application-controller and argocd-redis.

## Verification

- App status transitions to `Healthy` (timestamp in `.status.health.lastTransitionTime` advances)
- Resource tree in UI shows all green
