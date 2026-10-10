# Microservicio Java 21

Aplicación HTTP con dos réplicas, probes, configuración de Vault y manifiestos propios, sin Helm. Jenkins construye/publica una imagen en development y promueve **el mismo digest** a QA y producción.

| Endpoint | Resultado |
|---|---|
| `/health/live`, `/health/ready` | Estado del proceso |
| `/api/secret` | Variable del pipeline; redactada por defecto |
| `/api/config` | Propiedad del archivo CSI y flag VSO |

## Carpetas

- `src/`, `Dockerfile`: aplicación, pruebas Java 21 e imagen sin secretos incorporados.
- `k8s/`: manifiestos comunes; `environments/development`, `qa`, `production`: overlays Kustomize propios.
- `Jenkinsfile`, `scripts/`: build, lectura Vault, promoción verificada y rollback por entorno.
- `schemas/`, `.github/workflows/`: validación de Kubernetes/CRD, scripts y pruebas.
- `local-demo/`: perfil histórico de dos clústeres kind, actualmente detenido.

## Ramas y promoción

| Rama | Destino | Acción Jenkins |
|---|---|---|
| `develop` | development | Vault antes de test/build → una construcción/push → digest → deploy → `release.json` |
| `qa` | qa | Recupera un build develop exitoso → verifica árbol Git/digest → secreto QA → deploy |
| `main` | production | Recupera un build QA exitoso → verifica árbol Git/digest → secreto production → deploy |

El usuario decide cada avance: PR feature→develop, después develop→qa y qa→main. GitHub Actions valida PRs/push; no despliega. Jenkins ejecuta solo el destino de su rama, sin encadenar QA/producción. Las ramas locales develop/qa existen; cambios sin commit/publicación.

Para QA/main indicar `SOURCE_BUILD_NUMBER` del build anterior validado. El manifiesto registra digest, commit/árbol original y job/build/entorno validado. Se exige SUCCESS y coincidencia exacta del árbol Git del merge: los commits pueden diferir, el contenido no. Un árbol distinto, build fallido, otro job o tag mutable se rechaza. Si el build no se selecciona, la promoción se detiene; no adivina el artefacto. Conservar builds/artefactos hasta completar la promoción.

## Preparación

Seguir [README de herramientas](../despliegue-jenkins-vault/README.md). Configurar Jenkins Multibranch restringido a develop/qa/main, `AGENT_IMAGE`, `registry-credentials`, `promotion-reader` (usuario/API token solo lectura) y kubeconfig-development/qa/production con contexto exacto y SA limitado del clúster correspondiente. Revisión/protección de ramas y activación de jobs siguen pendientes; no se configuraron remotamente.

Aplicar cada overlay como administrador tras sustituir DNS interno Vault, imagen y CIDR de evaluación; instalar VSO/CSI y CA/ghcr-pull en cada clúster. Jenkins solo modifica Deployment y pipeline-env. Cada entorno lee `kv/environments/<entorno>/app` y su configuración CSI; no recompila al cambiar secretos. Si falla un rollout, restaura Deployment y Secret anteriores **solo de ese entorno**. Una primera instalación sin revisión previa queda fallida.

## Validación y estado

Pruebas: `python3 scripts/check-profile-parity.py`, `python3 scripts/test_deploy_environments.py`, `python3 scripts/test_release_promotion.py`, `sh scripts/test.sh` (Java 21) y `sh scripts/validate-manifests.sh` (kubectl/Docker). GitHub CI declara 5 pasos en un job.

La demo histórica acreditó development y rollback; no acredita estas promociones nuevas. El pipeline actualizado requiere validación declarativa e integración con Jenkins real, GHCR, Vault y tres EKS. AWS sigue sin verificación de despliegue; no se reinició la demo. Evidencia histórica: [demo local](../despliegue-jenkins-vault/local-demo/README.md).
