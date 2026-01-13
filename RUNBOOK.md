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
Terraform necesita un lugar seguro para guardar el "estado" de la infraestructura (el archivo `.tfstate`). No lo guardamos en local ni en Git. Creamos un **Bucket S3** (almacenamiento) y una **Tabla DynamoDB** (bloqueo para evitar colisiones si trabajamos en equipo).

### Pasos
1. **Verificar herramientas:** Asegúrate de tener instalados `aws-cli`, `terraform`, `terragrunt` y `kubectl`.
2. **Inicializar Backend Remoto:**
   Ejecuta este script automatizado para crear los recursos de soporte en AWS.

   ```bash
   ./scripts/setup_backend.sh
   ```

---

## 🏗️ Fase 1: Infraestructura Base (IaC)

### 1.1 Desplegar la Red (VPC)
**Contexto:** Antes del clúster, necesitamos las carreteras. Creamos una VPC (Virtual Private Cloud) con subnets públicas (para balanceadores) y privadas (para los nodos), y NAT Gateways para que los servidores privados puedan descargar actualizaciones de internet sin ser expuestos.

```bash
cd iac/live/dev/vpc
terragrunt init
terragrunt apply -auto-approve
```

### 1.2 Desplegar el Clúster (EKS)
**Contexto:** Ahora levantamos el "Control Plane" de Kubernetes (gestionado por AWS) y los "Worker Nodes" (donde vivirán nuestras aplicaciones).
*Nota: Este paso tarda aproximadamente 15 minutos. Es un buen momento para una pausa.*

```bash
cd ../eks
terragrunt init
terragrunt apply -auto-approve
```

### 1.3 Conectar la Terminal
**Contexto:** El clúster existe, pero tu ordenador no sabe cómo hablar con él. Este comando descarga el certificado digital y configura tu `kubectl` para autenticarse como administrador.

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-gitops-dev
kubectl get nodes
```
*Output esperado:* Una lista de nodos en estado `Ready`.

### 1.4 Instalar la Plataforma Base (ArgoCD)
**Contexto:** Instalamos ArgoCD usando Terraform (Helm Provider). ArgoCD será nuestro "Agente de GitOps", encargado de leer nuestro repositorio Git y sincronizar los cambios al clúster automáticamente.

```bash
cd ../platform
terragrunt init
terragrunt apply -auto-approve
```

---

## 🐙 Fase 2: GitOps (El Cerebro)

### 2.1 Bootstrapping (App of Apps)
**Contexto:** ArgoCD está instalado pero "vacío". En lugar de configurar 100 aplicaciones a mano, aplicamos **un solo manifiesto** llamado `root-app.yaml`. Este patrón le dice a ArgoCD: "Mira esta carpeta en Git y despliega todo lo que encuentres allí". Es la clave de la escalabilidad.

```bash
# Volver a la raíz del proyecto
cd ~/kubernetes-platform-engineering

# Inyectar la App Madre
kubectl apply -f gitops/control-plane/root-app.yaml
```

### 2.2 Verificar el Despliegue
**Contexto:** Accedemos a la consola visual de ArgoCD para confirmar que la magia ocurrió. Deberíamos ver cómo se crean automáticamente las apps de Backend, Frontend e Infraestructura.

1. **Obtener URL del Balanceador:**
   ```bash
   kubectl get svc -n argocd argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"; echo ""
   ```
2. **Obtener Contraseña de Admin:**
   ```bash
   echo "🔑 Password:" && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""
   ```
3. **Validación:** Entra al navegador. Debes ver 4 aplicaciones (Root, Backend, Frontend, External-Secrets) en estado **Healthy (Verde) 🟢**.

---

## 🔐 Fase 3: SecretOps (Seguridad Bancaria)

**Contexto:** Las contraseñas de base de datos NUNCA deben estar en Git (ni siquiera encriptadas). Usaremos **External Secrets Operator (ESO)**.
El flujo es: `AWS Secrets Manager (Origen)` -> `ESO (Intermediario)` -> `Kubernetes Secret (Destino)`.

### 3.1 Crear el Secreto en la Nube (AWS)
Creamos la contraseña "real" en la bóveda de seguridad de AWS.
```bash
aws secretsmanager create-secret \
    --name prod/db-password \
    --secret-string '{"username":"admin","password":"SuperSecretPassword123!"}' \
    --region us-east-1
```

### 3.2 Crear Identidad IAM (El Mensajero)
Creamos un usuario IAM específico que solo tiene permiso para "Leer Secretos". Esto sigue el principio de **Mínimo Privilegio**.
```bash
# Crear usuario y política
aws iam create-user --user-name eks-secrets-reader
aws iam attach-user-policy --user-name eks-secrets-reader --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Generar llaves y guardarlas temporalmente
aws iam create-access-key --user-name eks-secrets-reader > key.json
```

### 3.3 Conectar el Clúster con AWS
Le entregamos las credenciales del "Mensajero" al operador dentro de Kubernetes para que pueda ir a buscar el secreto.
*(Este script usa `jq` para leer el json automáticamente. Si no tienes jq, copia los valores del archivo key.json manualmente).*

```bash
# Leer valores
AK=$(jq -r .AccessKey.AccessKeyId key.json)
SK=$(jq -r .AccessKey.SecretAccessKey key.json)

# Crear el secreto puente en el namespace del operador
kubectl create secret generic awssm-secret \
  --from-literal=access-key="$AK" \
  --from-literal=secret-access-key="$SK" \
  -n external-secrets

# ⚠️ IMPORTANTE: Borrar las credenciales locales por seguridad
rm key.json
```

---

## ✅ Fase 4: Validación de la Plataforma

**Contexto:** Es el momento de la verdad. Verificaremos si la contraseña viajó desde AWS, fue desencriptada por el operador y está lista para ser usada por la aplicación, todo sin tocar un archivo de texto plano.

```bash
echo "🔓 La contraseña inyectada en el clúster es:"
kubectl get secret my-db-creds -n backend-ns -o jsonpath="{.data.db_password_k8s}" | base64 -d; echo ""
```

**Resultado Esperado:** Debes ver `SuperSecretPassword123!` en tu terminal.

---

## 🛑 Fase 5: Protocolo FinOps (Destrucción)

**⚠️ CRÍTICO:** Para garantizar **Costo $0.00** al finalizar, el orden de destrucción es vital. Si borras la VPC antes que los Balanceadores, AWS bloqueará la eliminación y seguirá cobrando.

### 5.1 Soft Delete (Limpieza de Aplicación)
Pedimos a Kubernetes que borre los balanceadores de carga (ELB) antes de morir.
```bash
kubectl delete application -n argocd --all
```

### 5.2 Limpieza Manual de Seguridad
Borramos los recursos que creamos a mano (AWS CLI) ya que Terraform no los conoce.
```bash
# Borrar secreto de la bóveda
aws secretsmanager delete-secret --secret-id prod/db-password --force-delete-without-recovery --region us-east-1

# Borrar usuario IAM y sus access keys
AK_ID=$(aws iam list-access-keys --user-name eks-secrets-reader --query 'AccessKeyMetadata[0].AccessKeyId' --output text)
aws iam delete-access-key --user-name eks-secrets-reader --access-key-id $AK_ID
aws iam detach-user-policy --user-name eks-secrets-reader --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
aws iam delete-user --user-name eks-secrets-reader
```

### 5.3 Nuke Load Balancers (Seguro de Vida)
Ejecuta este script para barrer cualquier balanceador huérfano que haya quedado.
```bash
./scripts/nuke_loadbalancers.sh
```

### 5.4 Destrucción de Infraestructura (Terraform)
Destruimos las capas en orden inverso a la creación.

1. **Plataforma:**
   ```bash
   cd iac/live/dev/platform && terragrunt destroy -auto-approve
   ```
2. **Clúster EKS:** (Espera ~15 mins)
   ```bash
   cd ../eks && terragrunt destroy -auto-approve
   ```
3. **Red VPC:**
   ```bash
   cd ../vpc && terragrunt destroy -auto-approve
   ```
   *Si falla la VPC, ejecuta `cd ~/kubernetes-platform-engineering && ./scripts/nuke_vpc.sh <VPC_ID>` y reintenta.*

### 5.5 Auditoría Forense (Deep Sweep)
El paso final. Este script escanea toda la región buscando residuos (Discos, IPs, Llaves KMS).
```bash
cd ~/kubernetes-platform-engineering
./scripts/deep_sweep_finops.sh
```
**Meta:** Todo debe decir **LIMPIO** o **PendingDeletion**.
