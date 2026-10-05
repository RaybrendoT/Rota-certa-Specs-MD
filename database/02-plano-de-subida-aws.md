# Plano de subida do banco na AWS

Objetivo: colocar o PostgreSQL do Rota Certa na AWS com as migrações aplicadas e um superusuário criado, deixando definido tudo o que os manifestos YAML (Kubernetes/Kustomize) vão precisar. Este plano vem **antes** dos YAML: cada decisão abaixo vira um valor nos manifestos.

Documentos relacionados: `01-mapa-do-banco.md` (o que existe no banco), `03-migrations-e-superuser.md` (migração 0007 e superusuário — renumerada; ver nota no documento), `04-postgres-exclusivo.md` (fim do fallback para SQLite, resolve P-04 — **já aplicado**), `05-plano-de-backup.md` (backup detalhado, resolve D6), `sql/` (papéis e verificação).

> **Não executado contra AWS/RDS.** Nada aqui foi rodado contra a AWS: o plano vem da leitura do código. A migração 0007 teve só a lógica conferida com um Django simulado; o SQL de `sql/` não foi executado. Trate os comandos como roteiro a validar num ambiente de teste. Duas mudanças de código **já foram aplicadas** ao repositório nesta sessão: P-04 (`04-postgres-exclusivo.md`) e P-09 (cópia da migração do superusuário, como `0007`) — os demais itens da Fase 0 continuam pendentes.

## 1. Decisões a fechar (com recomendação)

| # | Decisão | Opções | Recomendação | Impacto nos YAML |
|---|---------|--------|--------------|------------------|
| D1 | Onde roda o PostgreSQL | **A)** Amazon RDS · **B)** StatefulSet no cluster kubeadm | **A) RDS** | A: Service `ExternalName`/Endpoint para o host do RDS. B: StatefulSet + PVC + StorageClass |
| D2 | Segredos | Secret do Kubernetes · SSM Parameter Store / Secrets Manager | Secret do k8s na fase 1; migrar depois | `Secret` por papel (owner, app) e um para o superusuário |
| D3 | Quem roda `migrate` | Job do Kubernetes · `initContainer` do Deployment | **Job**, uma execução por release | `Job` com credencial do owner |
| D4 | Superusuário | migração com variáveis de ambiente · `createsuperuser --noinput` num Job | **Migração 0007** (pedido, já aplicada) | Variáveis só no Job de migrate |
| D5 | Dados iniciais | banco vazio · `seed_manaus_demo` | **Vazio** em produção; seed só em demo | Sem Job de seed no ambiente principal |
| D6 | Backup | backup por imagem (EBS/AMI) · backup tradicional (snapshot nativo do RDS/`pg_dump`/WAL) | **Backup tradicional** (snapshots do RDS com PITR + `pg_dump` em CronJob como segunda camada); imagem só entra como complemento se D1 for B — plano completo em `05-plano-de-backup.md` | `CronJob` de `pg_dump` com destino S3 (ambos os cenários); `VolumeSnapshot`/EBS extra só no cenário B |
| D7 | Ambientes | só produção · staging separado | Um banco na AWS agora; staging depois | Overlays do Kustomize (`base` + `aws`) |

**Por que RDS (D1).** O banco guarda contas de acesso e histórico operacional. O RDS já traz backup, restauração pontual, patches e monitoramento. Rodar Postgres dentro de um cluster montado com kubeadm exige resolver antes o armazenamento persistente (o kubeadm não instala StorageClass; seria preciso o driver EBS CSI com permissões IAM ou um provisionador local ligado a um único nó) e passa a ser sua a responsabilidade por backup, failover e memória. Em instâncias pequenas o Postgres e o Kubernetes disputam RAM: o kubeadm costuma exigir cerca de 1,7 GB no control-plane, então um `t3.micro` (1 GB) precisa de `--ignore-preflight-errors` ou de instância maior (confirme na documentação atual do kubeadm e no tamanho de instância que você usa). Se o objetivo da atividade for justamente ter tudo dentro do cluster, use a opção B; o restante do plano vale igual (só mudam rede, armazenamento e backup).

**Versão.** Django 5.2 exige PostgreSQL 14 ou superior. Escolha no console a versão principal mais recente suportada pelo RDS na sua região e mantenha a mesma no ambiente local (Docker) para evitar surpresas.

## 2. Arquitetura alvo

```
                 ┌──────────────────────────────── VPC ────────────────────────────────┐
 Internet ──►    │  sub-rede pública                     sub-redes privadas (2 AZs)    │
 (HTTPS)         │  ┌────────────────────────┐           ┌────────────────────────┐    │
                 │  │ EC2 (cluster kubeadm)  │  5432/TCP │ RDS PostgreSQL         │    │
                 │  │  ├─ Deployment backend │ ────────► │  db: rotacerta         │    │
                 │  │  ├─ Job migrate (1x)   │  SSL      │  papéis: owner / app   │    │
                 │  │  └─ Secrets            │           │  sem acesso público    │    │
                 │  └────────────────────────┘           └────────────────────────┘    │
                 │   SG-nodes                              SG-db: entra 5432 só de SG-nodes │
                 └───────────────────────────────────────────────────────────────────────┘
```

Regras: o RDS **não** é acessível pela internet; o Security Group do banco só aceita `5432` vindo do Security Group dos nós do cluster (e, temporariamente, do seu IP fixo ou de um bastion, para rodar os SQLs da fase 3). O RDS exige um *DB subnet group* com sub-redes em pelo menos duas zonas de disponibilidade, mesmo com instância única.

## 3. Fases

### Fase 0 — Preparar o código (bloqueios antes de qualquer YAML)

Itens do repositório que impedem ou tornam insegura a subida. Nenhum foi alterado por este trabalho.

| ID | Item | Onde | Por quê |
|----|------|------|---------|
| P-01 | Converter `requirements.txt` para UTF-8 e incluir `gunicorn` (e `whitenoise` para os estáticos do admin) | `requirements.txt` | Hoje está em UTF-16 (o `pip` pode falhar) e não há servidor de produção |
| P-02 | Definir `STATIC_ROOT` (+ `collectstatic` na imagem e WhiteNoise) | `config/settings.py` | O admin sem CSS/JS quebra a tela de login do superusuário |
| P-03 | `ALLOWED_HOSTS` e `CSRF_TRUSTED_ORIGINS` por variável de ambiente (hoje só `localhost:4200`) | `settings.py` | O login do admin por HTTPS falha com "Origin checking failed" |
| P-04 | ~~Eliminar o fallback para SQLite e aceitar `sslmode`/`CONN_MAX_AGE`~~ — **aplicado** | `build_database_config` | Cabia silenciosamente para SQLite sem `DATABASE_URL` (S-09) e ignorava parâmetros de query da URL; ver `04-postgres-exclusivo.md` |
| P-05 | Falhar se `SECRET_KEY` faltar quando `DEBUG=False` | `settings.py` | O padrão inseguro assinaria os tokens (review A11) |
| P-06 | `DEBUG=False` e `PASSWORD_RESET_RETURN_CODE_IN_RESPONSE=False` **explícitos** no ConfigMap | ConfigMap | O código de reset seguiria `DEBUG` (review A6) |
| P-07 | Criar `/api/health/` (200 se o banco responde) | novo | Não há endpoint de saúde para os probes |
| P-08 | Dockerfile (usuário não-root) e `.dockerignore` excluindo `.env`, `.venv`, `.idea`, `db.sqlite3`, `core_data.json` | novo | Evitar segredos e dados pessoais na imagem |
| P-09 | ~~Copiar a migração do superusuário para `core/migrations/`~~ — **aplicado**, como `0007_create_initial_superuser.py` (renumerada; ver `03-migrations-e-superuser.md`) | repositório | Ver `03-migrations-e-superuser.md` |
| P-10 | (Opcional) registrar os models em `core/admin.py` | `admin.py` | Hoje o admin só mostra Usuários e Grupos |

**Critério de aceite:** `docker build` conclui, o contêiner sobe com `DATABASE_URL` apontando para um Postgres local e responde em `/api/health/`.

### Fase 1 — Rede e segurança na AWS
- Definir região e VPC; sub-redes privadas em duas zonas para o banco.
- Criar `SG-nodes` (nós do cluster) e `SG-db` (entrada `5432` somente de `SG-nodes`).
- Criar o DB subnet group.
- **Aceite:** um nó do cluster alcança `<endpoint>:5432` (`nc -zv`); a internet não.

### Fase 2 — Instância de banco (D1-A: RDS)
- Motor PostgreSQL (versão da seção 1); classe pequena de uso geral/burstable; armazenamento gp3 pequeno (20 GB é folgado, ver `01-mapa-do-banco.md` §7) com auto-scaling ligado; **acesso público desligado**; criptografia em repouso ligada.
- Usuário mestre com senha gerada (guardada só no seu gerenciador de senhas); não será usado pela aplicação.
- Backups automáticos (retenção 7 dias) e janela de manutenção definidas; *deletion protection* ligada.
- Parameter group próprio: `timezone=UTC`, `log_min_duration_statement` (ex.: 500 ms), `log_connections` só durante a subida.
- Confirmar que a conexão SSL é exigida (padrão nas versões recentes).
- **Aceite:** conexão com `psql ... sslmode=require` usando o mestre.

### Fase 3 — Papéis e banco
Executar `sql/01_roles_e_banco.sql` com o usuário mestre, passando as senhas por variáveis:

```bash
psql "host=<endpoint> dbname=postgres user=<mestre> sslmode=require" \
     -v owner_pw="$ROTACERTA_OWNER_PASSWORD" -v app_pw="$ROTACERTA_APP_PASSWORD" \
     -f sql/01_roles_e_banco.sql
```

Resultado: banco `rotacerta`, papel `rotacerta_owner` (DDL, só no Job de migrate) e `rotacerta_app` (só DML, usado pelo backend). O "SUPERUSER" do servidor (mestre/`postgres`) fica **fora** da aplicação.
**Aceite:** `has_schema_privilege('rotacerta_app','public','CREATE')` retorna `false` (consulta 7 de `sql/02_verificacao.sql`).

### Fase 4 — Segredos e configuração do cluster
Criar (valores reais nunca vão para o Git):

| Objeto | Chaves |
|--------|--------|
| Secret `db-owner` | `DATABASE_URL=postgres://rotacerta_owner:<senha url-encoded>@<endpoint>:5432/rotacerta` |
| Secret `db-app` | `DATABASE_URL=postgres://rotacerta_app:<senha url-encoded>@<endpoint>:5432/rotacerta` |
| Secret `django` | `SECRET_KEY` (aleatória, ≥ 50 caracteres) |
| Secret `django-superuser` | `DJANGO_SUPERUSER_USERNAME`, `DJANGO_SUPERUSER_PASSWORD` (≥ 12), `DJANGO_SUPERUSER_EMAIL` |
| Secret `google-maps` | `GOOGLE_MAPS_API_KEY` (a chave do `.env.example` deve ser **rotacionada**) |
| ConfigMap `backend` | `DEBUG=False`, `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, `PASSWORD_RESET_RETURN_CODE_IN_RESPONSE=False`, `ACCESS_ACCOUNT_AUTO_CREATE=True`, `ACCESS_ACCOUNT_SYNC_EMAIL=True` |

A senha na URL precisa de *URL-encoding* (`@`, `:`, `/`, `#` etc.); o `settings.py` já faz `unquote`. Segredos do superusuário e do owner ficam **só** no Job de migrate, nunca no Deployment.

### Fase 5 — Migrações e superusuário (primeira subida)
1. **Snapshot manual** do RDS ("antes-do-primeiro-migrate").
2. Aplicar o Job `migrate` com `db-owner`, `django` e `django-superuser`, executando `python manage.py migrate --noinput` uma única vez (`restartPolicy: Never`, `backoffLimit` baixo, `ttlSecondsAfterFinished` para limpeza).
3. Esperar o Job concluir e ler os logs (nunca devem conter a senha).
4. Rodar `sql/02_verificacao.sql` e comparar com o mapa (21 tabelas, 17 FKs, `core` 0001–0007, 1 superusuário).
5. Só então liberar o Deployment do backend com `db-app`.

**Aceite:** consulta 6 mostra o superusuário; `/admin/` aceita o login; `rotacerta_app` consegue ler/escrever e não consegue criar tabelas.

### Fase 6 — Backend em execução e limpeza de credenciais
- Deployment com `db-app`, `SECRET_KEY`, ConfigMap, probes em `/api/health/`; `gunicorn` com poucos workers e `CONN_MAX_AGE` moderado (em instância pequena o limite de conexões é o gargalo; o papel `rotacerta_app` está limitado a 20).
- Entrar no admin, **trocar a senha do superusuário** e apagar o Secret `django-superuser` (a migração é idempotente e não recria).
- **Aceite:** smoke tests da API (login de uma `AccessAccount` de teste, `GET` autenticado) e do admin.

### Fase 7 — Operação
- Alarmes no CloudWatch: CPU, conexões, espaço livre e latência; alerta de falha de backup.
- Plano de backup e runbook de restauração completos: `05-plano-de-backup.md` (fases B0–B4, cadência mensal de teste, RTO/RPO de referência).
- Rotina: snapshot manual antes de cada migração em produção; janela de manutenção documentada.
- Rotação de senhas do owner/app com o procedimento de troca de Secret + reinício.

### Fase 8 — Evolução do esquema (depois do primeiro deploy)
Migrações 0008+ propostas em `03-migrations-e-superuser.md` §5 (unicidade de matrícula/licença por empresa, `token_version`, controle de tentativas do OTP, constraints de coordenadas, índice de eventos). Dependem de alterações no código e do check de duplicados; não fazem parte da primeira subida.

## 4. Sequência resumida (runbook)

```
Fase 0 código pronto ─► Fase 1 rede ─► Fase 2 RDS ─► Fase 3 SQL papéis
   ─► Fase 4 Secrets ─► snapshot ─► Fase 5 Job migrate (0001..0007 + superusuário)
   ─► verificação SQL ─► Fase 6 Deployment ─► troca de senha do superusuário
   ─► Fase 7 backups/alarmes
```

## 5. Riscos e mitigações

| Risco | Efeito | Mitigação |
|-------|--------|-----------|
| Dois `migrate` simultâneos | Conflito de DDL | Um único Job por release; nunca em `initContainer` com várias réplicas |
| Migração falha no meio | Banco parcialmente migrado | Postgres tem DDL transacional (cada migração é atômica); snapshot antes; reexecutar após corrigir |
| Senha do superusuário fraca ou vazada no Git | Acesso ao admin | Mínimo de 12 caracteres imposto na migração; Secret fora do repositório; trocar após o primeiro login |
| Aplicação com o papel dono do banco | Uma injeção de SQL alteraria o esquema | Papéis separados (owner só no Job) |
| Conexões esgotadas | 500 nas requisições | Papel com limite, `CONN_MAX_AGE`, poucos workers; pooler só se crescer |
| API pública durante a subida | — | `DEFAULT_PERMISSION_CLASSES` já exige autenticação (`IsAuthenticated`) no `settings.py` atual; o achado S-01/A2 (`AllowAny`) parece resolvido, mas confirme com um teste manual antes de expor à internet — não reauditado linha a linha nesta sessão |
| `DEBUG=True` herdado do `.env.example` | Código de reset exposto | Definir `DEBUG=False` e a flag do OTP explicitamente (P-06) |
| Dados pessoais em `core_data.json` na imagem | Vazamento | `.dockerignore` (P-08); não importar esse arquivo em produção |
| Perda de dados | — | Snapshots + `pg_dump` em segunda camada + teste de restauração mensal (`05-plano-de-backup.md`); deletion protection |
| `DATABASE_URL` ausente/errada num ambiente | Aplicação sobe silenciosamente em SQLite local, descartável e não compartilhado entre réplicas (S-09) | Fail-fast: `DATABASE_URL` obrigatória e restrita a `postgres(ql)://` (`04-postgres-exclusivo.md`) |

## 6. Insumos para os YAML

| Manifesto | Conteúdo mínimo |
|-----------|-----------------|
| `Namespace` | `rotacerta` |
| `Secret` ×5 | conforme a Fase 4 (valores fora do Git; usar `secretGenerator` sem commitar arquivos com valores reais) |
| `ConfigMap` | variáveis não sensíveis da Fase 4 |
| `Job` `migrate` | imagem do backend; `command: ["python","manage.py","migrate","--noinput"]`; `envFrom` de `db-owner`, `django`, `django-superuser`, ConfigMap; `restartPolicy: Never`; `backoffLimit`; `ttlSecondsAfterFinished` |
| `Deployment` backend | imagem do backend; `envFrom` de `db-app`, `django`, `google-maps`, ConfigMap; porta 8000; probes em `/api/health/`; `requests/limits` de memória modestos; usuário não-root |
| `Service` backend | ClusterIP 8000 |
| Acesso ao RDS | `Service` `ExternalName` para o endpoint (opção A) **ou** `StatefulSet` + `PVC` + `Service` headless + `StorageClass` (opção B) |
| `CronJob` de backup | `pg_dump` → S3, em ambas as opções (camada lógica); `VolumeSnapshot`/EBS extra só na opção B — ver `05-plano-de-backup.md` |
| `NetworkPolicy` | (se o CNI suportar) limitar saída do backend a `5432` e às APIs necessárias |
| Kustomize | `base/` (recursos) + `overlays/aws/` (imagem, ConfigMap, patches) |

Ordem de aplicação: `Namespace` → Secrets/ConfigMap → **Job `migrate`** (esperar `Complete`) → Deployment/Service.

## 7. Perguntas em aberto

1. **RDS ou banco dentro do cluster?** Muda a Fase 2, o armazenamento e o backup. A recomendação é RDS, mas a atividade pode exigir tudo no cluster.
2. ~~O "SUPERUSER" é o do Django admin? Hoje não existe perfil de gestor na API~~ — **respondida**: a migração 0007 cria o superusuário do Django admin; o administrador da API/frontend já existe como `AccessAccount.role = MANAGER` (`0006_access_account_role`, ver `03-migrations-e-superuser.md` §2) — são coisas diferentes, sem conflito.
3. **Qual domínio/HTTPS será usado?** Define `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS` e se o TLS termina no Ingress.
