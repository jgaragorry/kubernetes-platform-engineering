# ☸️ AWS EKS Enterprise Platform Engineering

![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Terragrunt](https://img.shields.io/badge/Terragrunt-5C4EE5?style=for-the-badge&logo=terragrunt&logoColor=white)
![ArgoCD](https://img.shields.io/badge/argocd-%23eb5b46.svg?style=for-the-badge&logo=argo&logoColor=white)
![External Secrets](https://img.shields.io/badge/External_Secrets-%23000000.svg?style=for-the-badge&logo=cncf&logoColor=white)
![FinOps](https://img.shields.io/badge/FinOps-Ready-00C853?style=for-the-badge&logo=google-sheets&logoColor=white)

## 📖 Descripción del Proyecto

Este repositorio contiene una implementación de referencia ("Golden Path") para una **Plataforma de Ingeniería de Grado Enterprise**.

El objetivo no es simplemente desplegar un clúster de Kubernetes, sino construir un **Ecosistema de Plataforma** completo, seguro y escalable que permita a los equipos de desarrollo desplegar software sin fricción, siguiendo las mejores prácticas de la industria: **GitOps**, **SecretOps** e **Infraestructura como Código (IaC)**.

### 🎯 Objetivos de Arquitectura
1.  **Inmutabilidad:** Toda la infraestructura se define en código (Terraform). Nada se hace "a mano" en la consola.
2.  **GitOps Puro:** El estado del clúster se sincroniza automáticamente desde Git usando ArgoCD. No más `kubectl apply` manuales.
3.  **Seguridad Bancaria:** Cero secretos en texto plano. Integración nativa con **AWS Secrets Manager** mediante External Secrets Operator.
4.  **Escalabilidad Dinámica:** Uso del patrón **App of Apps** que permite el Onboarding/Offboarding de equipos (Tenants) simplemente agregando o borrando archivos en Git.
5.  **FinOps & Disciplina:** Protocolos automatizados de destrucción y auditoría forense para garantizar costos cero cuando no está en uso.

---

## 🧩 Arquitectura GitOps: Patrón "App of Apps"

Este proyecto utiliza un diseño jerárquico donde una **Aplicación Madre (Root)** gestiona el ciclo de vida de todas las demás aplicaciones (Tenants). Esto permite desplegar la plataforma entera con un solo comando `kubectl apply`.

```mermaid
graph TD
    %% Estilos
    classDef user fill:#2e2e2e,stroke:#fff,stroke-width:2px,color:#fff;
    classDef root fill:#D946EF,stroke:#333,stroke-width:2px,color:#fff;
    classDef git fill:#F05032,stroke:#333,stroke-width:2px,color:#fff;
    classDef infra fill:#00C853,stroke:#333,stroke-width:2px,color:#fff;
    classDef apps fill:#326CE5,stroke:#333,stroke-width:2px,color:#fff;
    classDef secret fill:#FFC107,stroke:#333,stroke-width:2px,color:#000;

    %% Actores
    User((👷 Tú / Admin)):::user
    Git[["📂 GitHub Repo"]]:::git

    %% Flujo Principal
    subgraph Control_Plane [1. El Cerebro]
        Root("👑 Platform Root App"):::root
    end

    subgraph Tenants [2. Aplicaciones Hijas]
        Infra("⚙️ Infrastructure"):::infra
        Backend("📦 Backend Team"):::apps
        Frontend("💻 Frontend Team"):::apps
    end

    subgraph Operation [3. Operación Secreta]
        AWS[("☁️ AWS Secrets Manager")]:::secret
        K8sSecret[("🔐 K8s Native Secret")]:::secret
    end

    %% Conexiones con Orden
    User -->|1. kubectl apply| Root
    Root -->|2. Lee carpeta| Git
    Git -->|3. Detecta Archivos| Infra & Backend & Frontend
    Infra -->|4. Instala CRDs| Backend
    Backend -.->|5. Espera Infra| Infra
    Infra -->|6. Conecta con| AWS
    AWS -->|7. Inyecta Password| K8sSecret
    K8sSecret -->|8. Consume| Backend
```

**Explicación del Flujo de Trabajo:**
1.  **Bootstrapping:** El administrador despliega manualmente solo la `Platform Root App` (El Jefe).
2.  **Auto-Discovery:** La Root App vigila la carpeta `gitops/tenants/` en el repositorio Git.
3.  **Expansión:** ArgoCD detecta los manifiestos de los equipos (Backend, Frontend, Infra) y despliega sus aplicaciones automáticamente.
4.  **Gestión de Dependencias:** La aplicación de Infraestructura instala el *External Secrets Operator* antes que el resto.
5.  **Inyección de Secretos:** Una vez activo, el operador se conecta a AWS, descarga las credenciales de forma segura y las convierte en secretos nativos de Kubernetes (K8s Secret) para que el Backend las consuma sin fricción.

---

## 🏗️ Arquitectura de la Solución

La plataforma se divide en capas lógicas de responsabilidad:

### Capa 0: Infraestructura (AWS + Terraform/Terragrunt)
* **Red (VPC):** Diseño de 3 capas (Pública/Privada/Data) en Multi-AZ para alta disponibilidad.
* **Compute (EKS):** Clúster Kubernetes v1.29+ con Nodos Gestionados (Managed Node Groups) optimizados.
* **IAM:** Roles granulares con políticas de mínimo privilegio (IRSA).

### Capa 1: Plano de Control (ArgoCD)
* Motor de GitOps desplegado vía Terraform (Helm Provider).
* Gestión automatizada del ciclo de vida de las aplicaciones.
* Self-Healing: Si alguien borra un recurso manualmente, ArgoCD lo restaura al instante.

### Capa 2: Seguridad & Secretos (External Secrets Operator)
* **Source of Truth:** AWS Secrets Manager.
* **Sincronización:** El operador inyecta credenciales en tiempo real dentro de los Pods.
* **Rotación:** Permite rotar passwords en AWS sin redeployar las aplicaciones.

### Capa 3: Aplicaciones (Tenants)
Ejemplos de cargas de trabajo reales desplegadas:
* **Backend:** Go application con Redis.
* **Frontend:** Microservicio expuesto vía Load Balancer.

---

## 📂 Estructura del Repositorio

El proyecto sigue una estructura modular estricta para separar responsabilidades:

```text
.
├── gitops/                  # 🧠 El "Cerebro" de ArgoCD
│   ├── control-plane/       # Root App (Patrón App of Apps)
│   └── tenants/             # Definición de Microservicios (Backend, Frontend, Infra)
│
├── iac/                     # 🧱 Infraestructura como Código
│   ├── live/dev/            # Entorno de Desarrollo (Instanciación)
│   │   ├── vpc/             # Red
│   │   ├── eks/             # Clúster
│   │   └── platform/        # ArgoCD Base Installation
│   └── modules/             # Módulos reutilizables de Terraform
│
└── scripts/                 # 🛡️ Suite de Automatización y FinOps
    ├── setup_backend.sh     # Inicio del Lab (S3 + DynamoDB)
    ├── nuke_loadbalancers.sh# Limpieza de recursos huérfanos
    ├── nuke_vpc.sh          # Eliminación de dependencias de red
    └── deep_sweep_finops.sh # Auditoría Forense de Costos (Nivel Experto)
```

---

## 🚀 Inicio Rápido (Quickstart)

Para desplegar este laboratorio desde cero, sigue estrictamente el Runbook Maestro.

👉 **[VER RUNBOOK DE DESPLIEGUE (RUNBOOK.md)](./RUNBOOK.md)**

1.  **Pre-requisitos:** `aws-cli`, `terraform`, `kubectl`.
2.  **Tiempo de despliegue:** ~20 minutos.
3.  **Costo estimado:** ~$0.50 USD/hora (mientras esté encendido).

---

## 💰 Protocolo FinOps (Cierre y Destrucción)

Este proyecto incluye una suite de herramientas avanzadas para evitar "Costos Fantasma" en la nube. **NO EJECUTES `terraform destroy` SIN LEER ESTO**.

👉 **[VER PROTOCOLO DE DESTRUCCIÓN Y AUDITORÍA (FINOPS_PROTOCOL.md)](./FINOPS_PROTOCOL.md)**

El protocolo garantiza la eliminación de:
* Balanceadores de Carga huérfanos.
* Discos EBS y Snapshots.
* NAT Gateways y Elastic IPs.
* Llaves KMS y Log Groups.

---

## 👨‍💻 Autor

**Jesus Garagorry**
*Cloud Platform Architect | DevOps Engineer | FinOps Enthusiast*

---
*Este proyecto es parte de un portafolio de ingeniería avanzada en Kubernetes.*
