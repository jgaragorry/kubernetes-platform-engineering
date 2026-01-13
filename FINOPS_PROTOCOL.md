# 💰 FinOps Protocol: Destrucción Forense y Auditoría

![FinOps](https://img.shields.io/badge/FinOps-Protocol_Activated-00C853?style=for-the-badge&logo=google-sheets&logoColor=white)
![Cost](https://img.shields.io/badge/Target_Cost-$0.00-red?style=for-the-badge)

Este documento detalla el procedimiento operativo estándar (SOP) para el desmantelamiento de la plataforma. El objetivo es garantizar una limpieza absoluta de recursos en AWS, evitando costos ocultos ("Facturas Sorpresa") mediante barridos forenses automatizados.

---

## 📜 Inventario de Herramientas FinOps

La carpeta `/scripts` contiene una suite de utilidades desarrolladas específicamente para este entorno:

| Script | Propósito | Nivel de Riesgo |
| :--- | :--- | :--- |
| **`nuke_loadbalancers.sh`** | **El Salva-VPCs.** Elimina Load Balancers (CLB/ALB) que Kubernetes deja huérfanos al borrar Servicios. Si no se ejecuta, la VPC no podrá borrarse. | 🔴 Alto (Destructivo) |
| **`nuke_vpc.sh`** | Elimina dependencias de red "pegajosas" (Security Groups, ENIs) que suelen bloquear a Terraform. | 🔴 Alto (Destructivo) |
| **`nuke_zombies.sh`** | Limpia residuos menores como Log Groups de CloudWatch y Alias de llaves KMS. | 🟡 Medio |
| **`deep_sweep_finops.sh`** | **El Juez Final.** Realiza un escaneo de la región completa (`us-east-1`) buscando cualquier recurso activo (Discos, IPs, KMS, Snapshots). | 🟢 Lectura (Auditoría) |

---

## 🧨 Protocolo de Ejecución (Orden Estricto)

Para evitar bloqueos de dependencia (Deadlocks), sigue este orden exacto.

### Paso 1: Soft Delete (Nivel Aplicación)
Pedimos al clúster que elimine los recursos de aplicación antes de destruir los servidores.
```bash
kubectl delete application -n argocd --all
```

### Paso 2: Limpieza de Seguridad (Recursos Manuales)
Terraform no conoce los recursos que creamos vía CLI (Secretos y IAM Users), por lo que debemos borrarlos explícitamente.

```bash
# 1. Eliminar Secreto
aws secretsmanager delete-secret --secret-id prod/db-password --force-delete-without-recovery --region us-east-1

# 2. Desmantelar Usuario IAM
# (Reemplazar 'eks-secrets-reader' si usaste otro nombre)
AK_ID=$(aws iam list-access-keys --user-name eks-secrets-reader --query 'AccessKeyMetadata[0].AccessKeyId' --output text)
aws iam delete-access-key --user-name eks-secrets-reader --access-key-id $AK_ID
aws iam detach-user-policy --user-name eks-secrets-reader --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
aws iam delete-user --user-name eks-secrets-reader
```

### Paso 3: Barrido de Balanceadores (Pre-Destroy)
Ejecuta esto **antes** de destruir el clúster o la VPC.
```bash
./scripts/nuke_loadbalancers.sh
```

### Paso 4: Destrucción de Infraestructura (Terraform)
En orden inverso a la creación:

1.  **Plataforma (Helm Charts):**
    ```bash
    cd iac/live/dev/platform && terragrunt destroy -auto-approve
    ```
2.  **Clúster EKS (Compute):**
    *(Paciencia: ~10-15 mins)*
    ```bash
    cd ../eks && terragrunt destroy -auto-approve
    ```
3.  **Red VPC (Networking):**
    ```bash
    cd ../vpc && terragrunt destroy -auto-approve
    ```
    *❌ ¿Error `DependencyViolation`?* Ejecuta `./scripts/nuke_vpc.sh <VPC_ID>` y reintenta.

### Paso 5: Auditoría Forense (Deep Sweep)
El paso definitivo para poder dormir tranquilo.
```bash
cd ~/kubernetes-platform-engineering
./scripts/deep_sweep_finops.sh
```

---

## 🔍 Interpretación de Resultados

El laboratorio se considera "Cerrado" solo cuando `deep_sweep_finops.sh` devuelve **LIMPIO** en todas las categorías.

* **⚠️ Llaves KMS Encontradas:** Si aparecen en estado `Enabled`, debes programar su borrado:
    ```bash
    aws kms schedule-key-deletion --key-id <KEY_ID> --pending-window-in-days 7 --region us-east-1
    ```
    *(Las llaves en estado `PendingDeletion` no generan costos).*

* **⚠️ Elastic IPs:** Si aparecen IPs no asociadas, bórralas manualmente en la consola de EC2 > Elastic IPs.
