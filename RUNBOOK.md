# 📘 AWS EKS Enterprise Platform - Master Runbook

![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![ArgoCD](https://img.shields.io/badge/argocd-%23eb5b46.svg?style=for-the-badge&logo=argo&logoColor=white)
![External Secrets](https://img.shields.io/badge/External_Secrets-%23000000.svg?style=for-the-badge&logo=cncf&logoColor=white)
![FinOps](https://img.shields.io/badge/FinOps-00C853?style=for-the-badge&logo=google-sheets&logoColor=white)

Este documento es la guía definitiva para desplegar, operar y destruir la plataforma de ingeniería basada en Kubernetes (EKS), GitOps (ArgoCD) y SecretOps (External Secrets).

---

## 📋 Tabla de Contenidos
1. [Fase 0: Prerrequisitos y Backend](#-fase-0-prerrequisitos-y-backend)
2. [Fase 1: Infraestructura Base (IaC)](#-fase-1-infraestructura-base-iac)
3. [Fase 2: GitOps (El Cerebro)](#-fase-2-gitops-el-cerebro)
4. [Fase 3: SecretOps (Seguridad Bancaria)](#-fase-3-secretops-seguridad-bancaria)
5. [Fase 4: Validación de la Plataforma](#-fase-4-validación-de-la-plataforma)
6. [Fase 5: Protocolo FinOps (Destrucción)](#-fase-5-protocolo-finops-destrucción)

---

## 🛠️ Fase 0: Prerrequisitos y Backend

### 💡 ¿Qué estamos haciendo?
Terraform necesita un lugar seguro para guardar el "estado" de la infraestructura. Ejecutamos este script para crear un Bucket S3 y una tabla DynamoDB.

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
**Contexto:** Instalamos el motor de GitOps.
```bash
cd ../platform
terragrunt init
terragrunt apply -auto-approve
```

---

## 🐙 Fase 2: GitOps (El Cerebro)

### 2.1 Bootstrapping (App of Apps)
**Contexto:** Conectamos ArgoCD al repositorio Git para que despliegue todas las aplicaciones automáticamente.
```bash
# Volver a la raíz
cd ~/kubernetes-platform-engineering

# Inyectar la App Madre
kubectl apply -f gitops/control-plane/root-app.yaml
```

### 2.2 Verificar el Despliegue
**Contexto:** Validamos visualmente que las apps (Backend, Frontend, External-Secrets) se estén creando.
```bash
# Obtener URL
kubectl get svc -n argocd argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"; echo ""

# Obtener Password Admin
echo "🔑 Password:" && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""
```

---

## 🔐 Fase 3: SecretOps (Seguridad Bancaria)

**Contexto:** Inyectaremos credenciales desde AWS Secrets Manager directamente a Kubernetes.

### 3.1 Crear el Secreto en la Nube (AWS)
```bash
aws secretsmanager create-secret \
    --name prod/db-password \
    --secret-string '{"username":"admin","password":"SuperSecretPassword123!"}' \
    --region us-east-1
```

### 3.2 Crear Identidad IAM (El Mensajero)
```bash
# Crear usuario y política de lectura
aws iam create-user --user-name eks-secrets-reader
aws iam attach-user-policy --user-name eks-secrets-reader --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Generar llaves (key.json)
aws iam create-access-key --user-name eks-secrets-reader > key.json
```

### 3.3 Check de Sincronización (⚠️ Anti-Race Condition)
**Contexto:** ArgoCD puede tardar unos segundos en crear el namespace `external-secrets`. Esperamos a que exista antes de continuar.
```bash
echo "⏳ Esperando a que ArgoCD cree el namespace..."
until kubectl get ns external-secrets >/dev/null 2>&1; do echo "zzZZzz..."; sleep 5; done
echo "✅ Namespace detectado. Procediendo."
```

### 3.4 Conectar el Clúster con AWS
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

# Borrar credenciales locales
rm key.json
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

## 🛑 Fase 5: Protocolo FinOps (Destrucción)

**⚠️ IMPORTANTE:** Sigue este orden estricto para evitar costos.

### 5.1 Soft Delete (Limpieza de Apps)
```bash
kubectl delete application -n argocd --all
```

### 5.2 Limpieza Manual de Seguridad
```bash
# Borrar Secreto AWS
aws secretsmanager delete-secret --secret-id prod/db-password --force-delete-without-recovery --region us-east-1

# Borrar Usuario IAM
AK_ID=$(aws iam list-access-keys --user-name eks-secrets-reader --query 'AccessKeyMetadata[0].AccessKeyId' --output text)
aws iam delete-access-key --user-name eks-secrets-reader --access-key-id $AK_ID
aws iam detach-user-policy --user-name eks-secrets-reader --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
aws iam delete-user --user-name eks-secrets-reader
```

### 5.3 Nuke Load Balancers (Crucial)
```bash
./scripts/nuke_loadbalancers.sh
```

### 5.4 Destrucción Infraestructura (Terraform)
```bash
# 1. Plataforma
cd iac/live/dev/platform && terragrunt destroy -auto-approve
# 2. Clúster (Espera ~15 mins)
cd ../eks && terragrunt destroy -auto-approve
# 3. Red
cd ../vpc && terragrunt destroy -auto-approve
```

### 5.5 Auditoría Forense Final
```bash
cd ~/kubernetes-platform-engineering
./scripts/deep_sweep_finops.sh
```
