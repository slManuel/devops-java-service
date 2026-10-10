# Microservicio Java 21 y pipeline Jenkins

Servicio HTTP Java 21 sin dependencias externas, dos réplicas, NLB y manifiestos propios. No usa Helm. El Jenkinsfile obtiene `DEMO_MESSAGE` de Vault **antes** de compilar/probar y construir la imagen; publica en GHCR y despliega por digest. Nunca pasa el valor como Docker ARG ni lo incorpora a la imagen.

| Endpoint | Resultado |
|---|---|
| `/health/live`, `/health/ready` | HTTP200 cuando el proceso inició con su configuración |
| `/api/secret` | Valor inyectado por env; por defecto redactado. `EXPOSE_DEMO_VALUE=true` sólo para un dato de demostración y CIDR evaluador restringido |
| `/api/config` | Propiedad leída del archivo local `application.properties` (montaje CSI) y flag inyectado por VSO |

`DEMO_MESSAGE` y `demo.property` son obligatorios al arrancar. El contenedor corre como 10001, sin capacidades y filesystem raíz de sólo lectura. Configuración, tmpfs, probes, requests/limits, SA, RBAC y namespace están en `k8s/`.

## Comprobaciones locales

```sh
docker run --rm --user "$(id -u):$(id -g)" -e DEMO_MESSAGE=local-validation -v "$PWD:/src" -w /src eclipse-temurin:21-jdk sh scripts/test.sh
docker build -t devops-java-service:validation .
sh scripts/validate-manifests.sh
```

SmokeTest arranca un proceso real y comprueba HTTP readiness, método rechazado, propiedad local, JSON y redacción. Las imágenes base están fijadas por digest en Dockerfile. GitHub CI ejecuta pruebas, build, sintaxis shell y Kubeconform contra Kubernetes 1.36 y esquemas de CRD **VSO1.6.0/CSI1.6.1** incluidos en `schemas/`; son derivados de manifests upstream, no un operador propio. El Jenkinsfile también se compiló con Groovy 2.4.21 del Jenkins LTS elegido; la validación declarativa y ejecución integrada quedan pendientes de Jenkins activo.

## Preparación y ejecución

Seguir [operación del repo de instalación](https://github.com/slManuel/despliegue-jenkins-vault/blob/main/docs/OPERACION.md). No aplicar archivos con `REPLACE_` ni el CIDR documental. Vault se alcanza desde micro por **NLB interno TCP**, con CA y verificación de SAN configurada; el DNS ClusterIP de tools no cruza entre clústeres. Instalar VSO, CSI driver y provider desde aquel repo con Kustomize. Los tres usan versiones fijas; prueba funcional con EKS/JWT pendiente por bloqueo AWS.

Aplicar namespace/identity/CA/CR de Vault y configurar credenciales Jenkins `registry-credentials`, `kubeconfig-development`, lectura del repo privado y parámetro `AGENT_IMAGE` publicado. La credencial kubeconfig usa context `development`, endpoint privado y SA temporal con RBAC limitado; renovar antes de expirar. Sustituir `REPLACE_VAULT_INTERNAL_DNS`, permitir CIDR del evaluador en Service, crear `ghcr-pull`. Jenkins sustituye `REPLACE_COMMIT` de Deployment por digest al desplegar, no se aplica la imagen placeholder.

Pipeline: checkout → JWT proyectado de `jenkins-pipeline` (600s) → login Vault JWT mount deployment → lectura limitada del KV y revocación token → pruebas/build rootless → push imagen inmutable → backup en memoria de Deployment/Secret actual → actualización → rollout y dos réplicas listas. El agente no usa Docker socket ni privileged. BuildKit rootless tiene excepción seccomp Unconfined y no-process-sandbox; sólo código confiable. Secrets de trabajo están en emptyDir Memory y se truncan al finalizar; no se archivan valores. El job debe configurarse para no retener workspace de agentes eliminados.

Si falla una actualización, `rollback.sh` restaura spec y Secret anteriores. Fallos antes del deploy no intentan rollback; una primera instalación fallida no tiene versión anterior y queda fallida para corregir. El pipeline no crea namespaces, identidades, operadores o Services con su credencial restringida.

## Estado y evidencia

Pruebas Java, construcción Docker, sintaxis shell/Groovy y schemas se verifican localmente y en CI. No hay evidencia todavía de pods, NLB, login JWT, reconciliación VSO, archivo CSI o rollback real: AWS no permite lanzar nodos y falta estación con acceso al API privado. La rúbrica se puede trazar al código, pero no se declara cumplida en ejecución.

Para la evaluación, guardar salidas **sin secretos** de `kubectl get pods/deployment/service`, condiciones VaultStaticSecret, SecretProviderClassPodStatus, endpoints con datos no sensibles y log del rollback de una revisión de prueba. No publicar kubeconfig, Secret YAML, estados, claves unseal o token root. Opcional de CronJob exportador no implementado.
