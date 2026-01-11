#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

REGION="us-east-1"

echo -e "${YELLOW}=================================================================${NC}"
echo -e "${RED}🕵️‍♂️  DEEP SWEEP FINOPS - Análisis Forense Profundo ($REGION)${NC}"
echo -e "${YELLOW}     Buscando residuos ocultos que Terragrunt suele ignorar...${NC}"
echo -e "${YELLOW}=================================================================${NC}"

# 1. EBS Volumes (Discos)
echo -ne "🔍 Buscando Volúmenes EBS 'Available' (Huérfanos)... "
VOLUMES=$(aws ec2 describe-volumes --region $REGION --filters Name=status,Values=available --query "Volumes[*].{ID:VolumeId,Size:Size}" --output text)
if [ -z "$VOLUMES" ]; then echo -e "${GREEN}LIMPIO${NC}"; else echo -e "${RED}⚠️ ENCONTRADOS:${NC}\n$VOLUMES"; fi

# 2. Elastic IPs (Direcciones IP estáticas no usadas)
echo -ne "🔍 Buscando Elastic IPs sin asociar... "
EIPS=$(aws ec2 describe-addresses --region $REGION --query "Addresses[?AssociationId==null].{IP:PublicIp,AllocId:AllocationId}" --output text)
if [ -z "$EIPS" ]; then echo -e "${GREEN}LIMPIO${NC}"; else echo -e "${RED}⚠️ ENCONTRADOS:${NC}\n$EIPS"; fi

# 3. Snapshots (Copias de seguridad de discos)
echo -ne "🔍 Buscando Snapshots de EBS (Owned by me)... "
# Filtramos por owner-id self para no ver los públicos de AWS
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNAPS=$(aws ec2 describe-snapshots --region $REGION --owner-ids $ACCOUNT_ID --query "Snapshots[*].{ID:SnapshotId,Vol:VolumeId}" --output text)
if [ -z "$SNAPS" ]; then echo -e "${GREEN}LIMPIO${NC}"; else echo -e "${RED}⚠️ ENCONTRADOS:${NC}\n$SNAPS"; fi

# 4. CloudWatch Log Groups (Logs de EKS)
echo -ne "🔍 Buscando Grupos de Logs de EKS (/aws/eks/*)... "
LOGS=$(aws logs describe-log-groups --region $REGION --log-group-name-prefix "/aws/eks/" --query "logGroups[*].logGroupName" --output text)
if [ -z "$LOGS" ]; then echo -e "${GREEN}LIMPIO${NC}"; else echo -e "${RED}⚠️ ENCONTRADOS:${NC}\n$LOGS"; fi

# 5. KMS Keys (Llaves Customer Managed)
echo -ne "🔍 Buscando Llaves KMS Customer Managed... "
# Listamos llaves y filtramos las que tienen descripción del lab (para no borrar llaves default de AWS)
KEYS=$(aws kms list-keys --region $REGION --query "Keys[*].KeyId" --output text)
FOUND_KEYS=""
for key in $KEYS; do
    DESC=$(aws kms describe-key --key-id $key --region $REGION --query "KeyMetadata.Description" --output text 2>/dev/null)
    if [[ "$DESC" == *"eks-gitops"* ]]; then
        STATE=$(aws kms describe-key --key-id $key --region $REGION --query "KeyMetadata.KeyState" --output text)
        if [[ "$STATE" != "PendingDeletion" ]]; then
             FOUND_KEYS+="$key ($STATE) "
        fi
    fi
done

if [ -z "$FOUND_KEYS" ]; then echo -e "${GREEN}LIMPIO${NC}"; else echo -e "${RED}⚠️ ENCONTRADOS:${NC}\n$FOUND_KEYS"; fi

# 6. Load Balancers (Doble check final)
echo -ne "🔍 Re-verificando Load Balancers (Classic & V2)... "
ELB=$(aws elb describe-load-balancers --region $REGION --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text)
ELBV2=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[*].LoadBalancerName" --output text)
if [ -z "$ELB" ] && [ -z "$ELBV2" ]; then echo -e "${GREEN}LIMPIO${NC}"; else echo -e "${RED}⚠️ ENCONTRADOS:${NC}\n$ELB $ELBV2"; fi

# 7. NAT Gateways (El asesino silencioso de billeteras)
echo -ne "🔍 Buscando NAT Gateways (Estado: Available)... "
NATS=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text)
if [ -z "$NATS" ]; then echo -e "${GREEN}LIMPIO${NC}"; else echo -e "${RED}⚠️ ENCONTRADOS:${NC}\n$NATS"; fi

echo -e "${YELLOW}=================================================================${NC}"
echo -e "🏁 Análisis completado. Si todo está ${GREEN}LIMPIO${NC}, costo = $0.00."
