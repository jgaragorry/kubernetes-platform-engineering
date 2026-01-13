# 📘 AWS EKS Enterprise Platform - Master Runbook

![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![ArgoCD](https://img.shields.io/badge/argocd-%23eb5b46.svg?style=for-the-badge&logo=argo&logoColor=white)
![External Secrets](https://img.shields.io/badge/External_Secrets-%23000000.svg?style=for-the-badge&logo=cncf&logoColor=white)
![FinOps](https://img.shields.io/badge/FinOps-00C853?style=for-the-badge&logo=google-sheets&logoColor=white)

Este documento es la guía definitiva para desplegar, operar y destruir la plataforma. Está optimizado para **prevenir Race Conditions** inyectando los secretos antes del despliegue de aplicaciones.

---

## 📋 Tabla de Contenidos
1. [Fase 0: Prerrequisitos y Backend](#-fase-0-prerrequisitos-y-backend)
2. [Fase 1: Infraestructura Base (IaC)](#-fase-1-infraestructura-base-iac)
3. [Fase 2: SecretOps (Preparación de Seguridad)](#-fase-2-secretops-preparación-de-seguridad)
4. [Fase 3: GitOps (Bootstrapping)](#-fase-3-gitops-bootstrapping)
5. [Fase 4: Validación de la Plataforma](#-fase-4-validación-de-la-plataforma)
6. [🌟 Fase Bonus: Day 2 Operations](#-fase-bonus-day-2-operations-escalamiento)
7. [🛑 Fase 5: Protocolo FinOps (Destrucción Total)](#-fase-5-protocolo-finops-destrucción-total)

---

## 🛠️ Fase 0: Prerrequisitos y Backend

### 💡 ¿Qué estamos haciendo?
Inicializamos el almacenamiento remoto para Terraform (S3 + DynamoDB).

### Pasos
1. **Verificar herramientas:** Asegúrate de tener `aws-cli`, `terraform`, `terragrunt` y `kubectl`.
2. **Inicializar Backend:**
   ```bash
   ./scripts/setup_backend.sh
   ```

---

## 🏗️ Fase 1: Infraestructura Base (IaC)

### 1.1 Desplegar la Red (VPC)
**Contexto:** Creamos la red aislada (VPC) con subnets públicas y privadas.
```bash
cd iac/live/dev/vpc
terragrunt init
terragrunt apply -auto-approve
```

### 1.2 Desplegar el Clúster (EKS)
**Contexto:** Levantamos el Control Plane de Kubernetes y los Nodos.
*Nota: Tarda ~15 mins. Buen momento para una pausa.*
```bash
cd ../eks
terragrunt init
terragrunt apply -auto-approve
```

### 1.3 Conectar la Terminal
**Contexto:** Configuramos `kubectl` para hablar con el nuevo clúster.
```bash
aws eks update-kubeconfig --region us-east-1 --name eks-gitops-dev
kubectl get nodes
```

### 1.4 Instalar Plataforma (ArgoCD)
**Contexto:** Instalamos el motor de GitOps base.
```bash
cd ../platform
terragrunt init
terragrunt apply -auto-approve
```

---

## 🔐 Fase 2: SecretOps (Preparación de Seguridad)

**Contexto:** Preparamos las credenciales *antes* de desplegar las aplicaciones para evitar errores de sincronización (Race Conditions).

### 2.1 Crear el Secreto en la Nube (AWS)
```bash
# Volver a la raíz del proyecto
cd ~/kubernetes-platform-engineering

aws secretsmanager create-secret \
    --name prod/db-password \
    --secret-string '{"username":"admin","password":"SuperSecretPassword123!"}' \
    --region us-east-1
```

### 2.2 Crear Identidad IAM (El Mensajero)
```bash
# Crear usuario y política de lectura
aws iam create-user --user-name eks-secrets-reader
aws iam attach-user-policy --user-name eks-secrets-reader --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Generar llaves (key.json)
aws iam create-access-key --user-name eks-secrets-reader > key.json
```

### 2.3 Preparar Namespace (Inyección Preventiva)
Creamos el namespace manualmente para poder inyectar el secreto antes de que ArgoCD llegue.
```bash
kubectl create ns external-secrets --dry-run=client -o yaml | kubectl apply -f -
```

### 2.4 Conectar el Clúster con AWS
Inyectamos las credenciales del "Mensajero" en el clúster.
```bash
# Leer valores
AK=$(jq -r .AccessKey.AccessKeyId key.json)
SK=$(jq -r .AccessKey.SecretAccessKey key.json)

# Crear el secreto puente
kubectl create secret generic awssm-secret \
  --from-literal=access-key="$AK" \
  --from-literal=secret-access-key="$SK" \
  -n external-secrets

# Borrar credenciales locales (Seguridad)
rm key.json
```

---

## 🐙 Fase 3: GitOps (Bootstrapping)

**Contexto:** Ahora que los secretos ya existen, desplegamos la "Root App". ArgoCD encontrará todo listo y se pondrá en verde inmediatamente.

### 3.1 Desplegar App of Apps
```bash
kubectl apply -f gitops/control-plane/root-app.yaml
```

### 3.2 Verificar el Despliegue
**Contexto:** Validamos visualmente que las apps (Backend, Frontend, External-Secrets) se estén creando correctamente.
```bash
# Obtener URL de ArgoCD
kubectl get svc -n argocd argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"; echo ""

# Obtener Password Admin
echo "🔑 Password:" && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""
```

---

## ✅ Fase 4: Validación de la Plataforma

**Contexto:** Verificamos que la contraseña viajó mágicamente desde AWS hasta el Pod de la aplicación.
```bash
echo "🔓 La contraseña inyectada en el clúster es:"
kubectl get secret my-db-creds -n backend-ns -o jsonpath="{.data.db_password_k8s}" | base64 -d; echo ""
```
**Resultado Esperado:** `SuperSecretPassword123!`

---

## 🌟 Fase Bonus: Day 2 Operations (Escalamiento)

**Contexto:** Demostraremos la capacidad de la plataforma para agregar un nuevo equipo ("Marketing") y luego eliminarlo usando solo Git.

### 1. Onboarding (Crear Equipo)
Creamos la definición de la app y la subimos a Git.
```bash
# Crear estructura
mkdir -p gitops/tenants/marketing-team

# Crear App Manifest
cat <<EOF > gitops/tenants/marketing-team/apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: marketing-landing-page
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: [https://stefanprodan.github.io/podinfo](https://stefanprodan.github.io/podinfo)
    targetRevision: 6.7.0
    chart: podinfo
  destination:
    server: [https://kubernetes.default.svc](https://kubernetes.default.svc)
    namespace: marketing-ns
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# Push a Git
git add .
git commit -m "feat: onboard marketing team"
git push
```
*👉 Ve a ArgoCD y observa cómo aparece la nueva aplicación automáticamente.*

### 2. Offboarding (Eliminar Equipo)
Simulamos que el proyecto terminó. Borramos el archivo en Git para limpiar el clúster.
```bash
# Borrar archivo y carpeta
git rm gitops/tenants/marketing-team/apps.yaml
rm -rf gitops/tenants/marketing-team/

# Push a Git
git add .
git commit -m "chore: offboard marketing team"
git push
```
*👉 ArgoCD detectará el borrado y eliminará todos los recursos del clúster (Pruning).*

---

## 🛑 Fase 5: Protocolo FinOps (Destrucción Total)

**⚠️ ADVERTENCIA:** Esta fase es destructiva. Sigue los pasos en orden para garantizar que no queden costos residuales ("Costos Fantasma").

### 5.1 Soft Delete (Limpieza de Aplicaciones)
Primero eliminamos las apps para que los balanceadores de carga se liberen correctamente.
```bash
kubectl delete application -n argocd --all
# Espera 1 minuto para asegurar que los controladores de Ingress liberen los recursos
sleep 60
```

### 5.2 Limpieza de Seguridad (IAM & Secrets)
Este bloque borra el secreto en AWS y el usuario IAM, asegurándose de eliminar **todas** sus access keys primero.
```bash
# 1. Borrar Secreto en AWS Secrets Manager
aws secretsmanager delete-secret --secret-id prod/db-password --force-delete-without-recovery --region us-east-1

# 2. Borrar TODAS las Access Keys del usuario (Loop de seguridad)
for key in $(aws iam list-access-keys --user-name eks-secrets-reader --query 'AccessKeyMetadata[*].AccessKeyId' --output text); do
  echo "Borrando llave: $key"
  aws iam delete-access-key --user-name eks-secrets-reader --access-key-id $key
done

# 3. Desvincular políticas y borrar usuario
aws iam detach-user-policy --user-name eks-secrets-reader --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
aws iam delete-user --user-name eks-secrets-reader
```

### 5.3 Nuke Load Balancers (Red de Seguridad)
Si algún balanceador quedó huérfano, este script lo detecta y elimina.
```bash
./scripts/nuke_loadbalancers.sh
```

### 5.4 Destrucción Infraestructura (Orden Estricto)
Debemos destruir desde "afuera hacia adentro".

**Paso A: Plataforma (ArgoCD)**
```bash
cd iac/live/dev/platform
terragrunt destroy -auto-approve
```

**Paso B: Clúster EKS (Tarda ~15 mins)**
*Esto eliminará los Nodos (EC2) y el Plano de Control.*
```bash
cd ../eks
terragrunt destroy -auto-approve
```

**Paso C: Red (VPC)**
Intenta el borrado normal primero:
```bash
cd ../vpc
terragrunt destroy -auto-approve
```

🔴 **¿Fallo con `DependencyViolation`?**
Si el paso anterior falla porque la VPC tiene dependencias "zombies" (ENIs pegadas), ejecuta el script de rescate nuclear:
```bash
# Ejecutar desde la raíz del proyecto
cd ~/kubernetes-platform-engineering
./scripts/nuke_vpc.sh vpc-XXXXXXXX  # <--- Reemplaza con el ID de tu VPC
```
*Una vez corrido el script, vuelve a ejecutar `terragrunt destroy` en la carpeta vpc para finalizar.*

### 5.5 Backend Nuke (Opcional - Borrado Histórico)
Ejecuta esto **solo si quieres borrar el historial de Terraform** (S3 Bucket y DynamoDB Table). Si planeas volver a usar el lab pronto, puedes saltarte este paso (costo < $0.01/mes).
```bash
cd ~/kubernetes-platform-engineering
./scripts/nuke_backend_smart.sh
```

### 5.6 Auditoría Forense Final
El paso de la verdad. Ejecuta esto para confirmar que tu facturación será $0.00.
```bash
./scripts/finops_audit_extreme.sh
```
*Si todo sale vacío o "terminated", ¡felicidades! Has completado el ciclo.*
