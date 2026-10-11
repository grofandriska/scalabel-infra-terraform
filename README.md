# Scalable AWS infrastruktúra Terraformmal

Moduláris, skálázható AWS infrastruktúra: egy VPC változó számú public és private subnettel,
Internet és NAT Gatewayjel, subnetenként konfigurálható számú privát EC2 instance-szal és
tetszőleges számú bastion hosttal. A state S3-ban tárolódik, DynamoDB zárolással.

## Architektúra

```
                         Internet
                            │
                     ┌──────┴──────┐
                     │     IGW     │
                     └──────┬──────┘
  ┌─────────────────────────┼───────────────────── VPC 10.0.0.0/16 ─┐
  │  public-a (eu-central-1a)    │       public-b (eu-central-1b)    │
  │  ┌────────────┐  ┌────────┐  │       ┌────────────┐              │
  │  │ bastion-a  │  │ NAT GW │  │       │ bastion-b  │              │
  │  └─────┬──────┘  └───┬────┘  │       └─────┬──────┘              │
  │        │ SSH         │ 0.0.0.0/0           │ SSH                 │
  │  private-a (1a)      │               private-b (1b)              │
  │  ┌─────────────────┐ │               ┌─────────────────┐         │
  │  │ private-a-01    │◄┴──────────────►│ private-b-01    │         │
  │  │ private-a-02    │                 └─────────────────┘         │
  │  └─────────────────┘                                             │
  └──────────────────────────────────────────────────────────────────┘
```

Forgalom:
- **Te → bastion:** SSH, csak a saját IP-dről (`allowed_ssh_cidrs`).
- **Bastion → privát EC2:** SSH, csak a bastion security groupból.
- **Privát EC2 → internet:** a NAT Gatewayen keresztül (frissítések, SSM).

## Mappaszerkezet

```
.
├── bootstrap/                  # S3 bucket + DynamoDB tábla a remote state-hez (egyszer kell futtatni)
│   └── main.tf
├── modules/
│   ├── vpc/                    # VPC, subnetek, IGW, NAT GW, route table-ök, asszociációk
│   ├── ec2-instance/           # key pair, IAM role (SSM), security group, privát EC2-k
│   └── bastion/                # bastion security group + bastion hostok
├── versions.tf                 # Terraform és provider verziók, provider + default_tags
├── backend.tf                  # S3 backend (partial configuration)
├── variables.tf                # root változók validációkkal
├── locals.tf                   # adattranszformációk (kulcsfájl beolvasása, jump host)
├── main.tf                     # AMI lekérdezés és modulhívások
├── outputs.tf                  # formázott kimenetek
└── terraform.tfvars.example    # kitöltendő példa a saját értékekhez
```

Minden modul a szokásos három fájlból áll: `variables.tf` (bemenetek), `main.tf` (erőforrások),
`outputs.tf` (kimenetek).

## Tervezési döntések

### List → map → for_each

Minden többszörözhető erőforrás listát vagy mapot kap bemenetként, a `locals`-ban név szerinti
mappé alakítja, és `for_each`-csel hozza létre:

```hcl
locals {
  subnets = { for s in var.subnets : s.name => s }
}

resource "aws_subnet" "this" {
  for_each = local.subnets
  # ...
}
```

`count`-tal egy elem törlése a lista közepéről eltolná az indexeket, és a Terraform újraépítené
az utána következő erőforrásokat. Név szerinti kulccsal (`aws_subnet.this["private-a"]`) csak
az érintett erőforrás változik, a többi érintetlen marad.

### A komplex EC2 változó

Az `ec2_config` egy map: subnet név → darabszám és opcionális instance típus.

```hcl
ec2_config = {
  "private-a" = { instance_count = 2 }
  "private-b" = { instance_count = 1, instance_type = "t3.small" }
}
```

Az EC2 modul ezt stabil kulcsokra lapítja ki (flatten):

```hcl
locals {
  instances = merge(concat([{}], [
    for subnet, cfg in var.instances_per_subnet : {
      for i in range(cfg.instance_count) :
      format("%s-%02d", subnet, i + 1) => {
        subnet        = subnet
        instance_type = coalesce(cfg.instance_type, var.default_instance_type)
      }
    }
  ])...)
}
```

Eredmény: `private-a-01`, `private-a-02`, `private-b-01`. Ha a darabszámot 3-ról 2-re
csökkented, csak a `-03` törlődik.

Miért map of objects, és nem sima `map(number)`? A map kulcsa garantálja, hogy egy subnet ne
szerepeljen kétszer, az objektum pedig lehetővé teszi a subnetenként eltérő instance típust
a változó szerkezetének későbbi módosítása nélkül.

### Gatewayek a VPC modulban

Az IGW és a NAT GW szorosan kötődik a VPC-hez és a route table-ökhöz, külön modulban csak
sok ID-t kellene oda-vissza adogatni. A NAT GW helyét a subneten jelölöd (`nat_gateway = true`):

- **egy NAT** (alapbeállítás): olcsóbb, minden private subnet ezt használja,
- **AZ-nként egy NAT**: magasabb rendelkezésre állás.

A private subnetek automatikusan a saját AZ-jukban lévő NAT-ot választják, ha nincs ilyen,
akkor az elsőt. Public oldalon egy közös route table van, private oldalon subnetenként egy,
mert mindegyik más NAT-ra mutathat.

### Modulok közötti adatáramlás

```
              tfvars (var.*)
                   │
                   ▼
           ┌──────────────┐
           │  module.vpc  │
           └──────┬───────┘
      vpc_id, subnet_ids, public_subnet_ids
         ┌────────┴─────────┐
         ▼                  ▼
  ┌────────────┐  SG ID ┌────────────────┐
  │ module.ec2 │◄───────│ module.bastion │
  │            │───────►│                │
  └────────────┘key_name└────────────────┘
```

Az EC2 modul kapja a bastion security group ID-t, a bastion modul pedig az EC2 modulban létrehozott
kulcspár nevét. Ez nem körkörös függőség, mert a Terraform erőforrás szinten épít gráfot: a bastion
SG nem függ a kulcspártól, és fordítva.

### Biztonság

- A bastion SG csak a megadott IP-kről enged SSH-t, a `0.0.0.0/0`-t validáció tiltja.
- A privát EC2-k SG-je security group hivatkozással csak a bastionöktől enged SSH-t.
- A privát gépek nem kapnak publikus IP-t.
- IMDSv2 kötelező (`http_tokens = "required"`), a root diszkek titkosítottak (`gp3`).
- Csak a publikus kulcs kerül fel az AWS-be, a privát kulcs a saját gépen marad, a state-be sem kerül.
- Az AMI-t csak hivatalos Amazon forrásból kérdezzük le (`owners = ["amazon"]`).
- A privát EC2-k SSM role-t kapnak, így Session Managerrel SSH nélkül is elérhetők.
- A state S3-ban titkosítva, verziózva, publikus hozzáférés nélkül tárolódik.

### Hibakezelés

- **Változó-validációk:** érvényes CIDR-ek, egyedi subnet és bastion nevek, `public`/`private`
  típus, NAT csak public subneten, nemnegatív egész darabszám.
- **Precondition-ök a modulokban:** nem létező subnetre hivatkozó EC2 vagy nem public subnetbe tett
  bastion érthető hibaüzenettel áll meg már a `plan`-nél.
- **`check` blokk:** figyelmeztet, ha vannak private subnetek, de nincs NAT Gateway.
- **`ignore_changes = [ami]`:** egy új Amazon Linux kiadás nem okoz instance-cserét.
- **`prevent_destroy`:** a state bucket véletlen törlés ellen védett.

## Használat

### Előfeltételek

- Terraform >= 1.5
- AWS CLI beállított hitelesítéssel (`aws sts get-caller-identity` működik)
- SSH kulcspár: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519`

### 1. Remote state létrehozása (egyszer)

```bash
cd bootstrap
terraform init
terraform apply -var="bucket_name=<egyedi-bucket-nev>"
terraform output -raw backend_config > ../backend.hcl
cd ..
```

A bucket névnek globálisan egyedinek kell lennie. A bootstrap lokális state-tel fut, mert a
state tárolót nem lehet ugyanabban a projektben létrehozni, amelyik már abba menti a state-jét.

### 2. Saját értékek

```bash
cp terraform.tfvars.example terraform.tfvars
curl -s https://checkip.amazonaws.com
```

A `terraform.tfvars`-ban töltsd ki:
- `owner`: a neved (tagként kerül minden erőforrásra),
- `allowed_ssh_cidrs`: a saját IP-d `/32`-vel,
- `key_pair.public_key_path`: a publikus kulcsod útvonala.

### 3. Deploy

```bash
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Inkrementális teszteléshez először csak a hálózat:

```bash
terraform apply -target=module.vpc
terraform apply
```

### 4. Kimenetek

```bash
terraform output -raw summary
terraform output subnets
terraform output bastion_hosts
terraform output ec2_instances
terraform output ssh_commands
```

Példa:

```
Projekt:      scalable-infra (eu-central-1)
VPC:          vpc-00bbad44b5f6c7b34 (10.0.0.0/16)
Subnetek:     2 public, 2 private
NAT GW-k:     1
Bastionök:    2
EC2-k:        3
Kulcspár:     scalable-infra-key
```

### 5. SSH a bastionön keresztül

A kész parancsokat a `terraform output ssh_commands` adja. Az instance-ok indulása után várj
1–2 percet. Első csatlakozáskor fogadd el a bastion kulcsát közvetlen belépéssel:

```bash
ssh ec2-user@<BASTION_PUBLIC_IP>
exit
```

**A) ProxyJump (ajánlott, a kulcs nem kerül a bastionre):**

```bash
ssh -J ec2-user@<BASTION_PUBLIC_IP> ec2-user@<EC2_PRIVATE_IP>
```

**B) Agent forwarding:**

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh -A ec2-user@<BASTION_PUBLIC_IP>
# a bastionön:
ssh ec2-user@<EC2_PRIVATE_IP>
```

**Ellenőrzés a privát gépen:**

```bash
hostname -I                                   # a privát IP
ping -c 3 <MASIK_EC2_PRIVATE_IP>              # a gépek látják egymást
curl -sI https://aws.amazon.com | head -1     # internet a NAT-on át
```

> Megjegyzés: Flatpakként telepített szerkesztők (VS Code, IntelliJ) beépített termináljában
> az SSH nem tudja megjeleníteni a host key kérdést. Az SSH teszthez használj rendes
> rendszer terminált.

## Skálázás

Minden változtatás csak a `terraform.tfvars`-ban történik, a kódhoz nem kell nyúlni.

| Változtatás | Várt `plan` |
|---|---|
| Új elem a `subnets` listába | csak az új subnet, route table és asszociáció jön létre |
| Egy subnet törlése a listából | csak az a subnet és az asszociációja törlődik |
| `"private-a" = { instance_count = 3 }` | +1 instance: `private-a-03` |
| `instance_count` 3 → 2 | csak a `private-a-03` törlődik |
| Új bastion a `bastion_config` listába | csak az új bastion jön létre |
| `nat_gateway = true` a `public-b`-n is | +1 NAT és EIP, a `private-b` route-ja átáll |

## Tesztelés és takarítás

A projekt az alábbi módon lett tesztelve:

1. VPC modul önmagában (`-target=module.vpc`), majd egy subnet eltávolításával a scalability ellenőrzése.
2. Teljes `apply`, a formázott outputok ellenőrzése.
3. SSH a bastionön keresztül mindhárom privát gépre, ping és internet-elérés ellenőrzése.
4. EC2 darabszám módosítása, a `plan` csak az érintett instance-t mutatta.
5. `terraform destroy`.

```bash
terraform destroy
```

A NAT Gateway óradíjas és forgalomarányosan is számláz, ne hagyd feleslegesen futni.
A bootstrap bucketje `prevent_destroy`-jal védett, és külön projekthez tartozik, így a fő projekt
`destroy`-a nem érinti.

## Ismert figyelmeztetés

A Terraform 1.11+ az S3 backend `dynamodb_table` paraméterét elavultnak jelöli, mert az S3 backend
már natív zárolást is tud (`use_lockfile = true`). A projekt a feladat kérése miatt használja a
DynamoDB-s zárolást. Ez csak figyelmeztetés, a működést nem befolyásolja. Átállás esetén a
`backend.hcl`-ben a `dynamodb_table` sort cseréld `use_lockfile = true`-ra, majd:

```bash
terraform init -backend-config=backend.hcl -reconfigure
```