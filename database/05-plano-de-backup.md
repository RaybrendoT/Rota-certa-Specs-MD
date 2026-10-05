# Plano de desenvolvimento — backup do banco na AWS

Complementa `02-plano-de-subida-aws.md` (D6 e Fase 7, que citam backup em uma linha cada). Aqui: as duas estratégias — **backup por imagem** e **backup tradicional (nível de banco)** —, comparadas, com recomendação e um plano faseado.

## 1. As duas estratégias

### 1.1 Backup por imagem (nível de infraestrutura)

Captura o estado de um **volume/instância inteiros**: um EBS snapshot do disco onde o Postgres guarda os dados, ou uma AMI da instância. Na AWS, o mecanismo natural é **AWS Backup** ou **EBS Data Lifecycle Manager** agendando snapshots do volume.

| | |
|---|---|
| **O que captura** | O volume inteiro (dados do Postgres + o que mais estiver no disco) num instante |
| **Consistência** | *Crash-consistent* por padrão (como se a energia tivesse caído): o Postgres, ao subir de um snapshot assim, faz recovery do WAL como faria após uma queda de energia — funciona, mas não é garantidamente idêntico a um desligamento limpo. Para ficar *application-consistent* é preciso coordenar com o Postgres antes do snapshot (`pg_backup_start()`/`pg_backup_stop()`, ou uma ferramenta que faça isso, como o AWS Backup com pre/post scripts) |
| **Granularidade da restauração** | O volume inteiro. Não dá para restaurar uma tabela ou um registro isoladamente — sempre um novo volume/instância completos |
| **Ponto de restauração** | Só os instantes em que um snapshot foi tirado (ex.: a cada 6h) — sem recuperação para um segundo específico entre snapshots |
| **Portabilidade** | Presa à AWS (formato de snapshot EBS); não serve para migrar para outro provedor ou para restaurar localmente sem recriar a infraestrutura |
| **Aplica-se ao RDS?** | Não diretamente — no RDS você não tem acesso ao EBS por baixo. O RDS tem seu **próprio** mecanismo de snapshot (que é *tecnicamente* baseado em imagem do armazenamento, mas gerenciado pela AWS com consistência garantida e integrado ao PITR — ver 1.2) |
| **Quando faz sentido aqui** | Só se o Postgres rodar **dentro do cluster** (opção B da decisão D1), como um complemento ao backup nativo do banco — nunca como estratégia única |

### 1.2 Backup tradicional (nível de banco de dados)

Usa os mecanismos do próprio PostgreSQL (ou do RDS, que os empacota): `pg_dump` (lógico), `pg_basebackup`/WAL archiving (físico contínuo), ou snapshots automáticos do RDS (que combinam snapshot de armazenamento + WAL para dar PITR).

| | |
|---|---|
| **O que captura** | Só os dados do banco (não o disco inteiro) — como SQL/objetos (`pg_dump`) ou como estado binário do cluster de banco (`pg_basebackup`/snapshot do RDS) |
| **Consistência** | Sempre *application-consistent*: o Postgres coordena o próprio backup (`pg_dump` faz uma transação consistente; o RDS e o WAL archiving garantem um ponto transacionalmente válido) |
| **Granularidade da restauração** | RDS/`pg_basebackup`: o banco inteiro, mas com **PITR** (restaura para qualquer segundo dentro da janela de retenção, não só para o instante do snapshot). `pg_dump`: pode restaurar objetos/tabelas específicas (`pg_restore -t tabela`) |
| **Portabilidade** | `pg_dump` é o mais portável: um `.sql`/`.dump` roda em qualquer PostgreSQL, em qualquer provedor, até localmente. Snapshot do RDS não sai da AWS (mas pode ser copiado entre regiões/contas) |
| **Aplica-se ao RDS?** | Sim — é o mecanismo nativo dele (snapshots automáticos diários + WAL para PITR de até 5 minutos, dentro da janela de retenção) |
| **Quando faz sentido aqui** | Sempre — é a base da estratégia, em qualquer cenário de hospedagem |

## 2. Recomendação

**Backup tradicional (nível de banco) como estratégia principal, em qualquer cenário de hospedagem. Backup por imagem só entra, como complemento, se a Fase 2 do plano de subida escolher Postgres dentro do cluster em vez de RDS.**

Motivos:

1. O plano de subida (`02-plano-de-subida-aws.md`, D1) já recomenda RDS. No RDS, backup por imagem (EBS/AMI) **não é uma opção disponível** — você não vê o volume por baixo. O mecanismo nativo do RDS já é o backup tradicional, com PITR incluído.
2. Mesmo se a Fase 2 escolher Postgres dentro do cluster (opção B), o backup por imagem sozinho seria insuficiente: sem coordenação com o Postgres, um EBS snapshot é *crash-consistent*, não garante que dá para restaurar com segurança, e não tem PITR (só os instantes em que rodou). Nesse cenário, a base ainda deve ser um mecanismo nativo do Postgres (WAL archiving contínuo, por exemplo com `pgBackRest` ou `wal-g`, escrevendo em S3) — o EBS snapshot vira um segundo lastro, não a estratégia.
3. Um `pg_dump` lógico, além de ser o backup mais barato de operar, é a única cópia **portável**: serve tanto para restaurar fora da AWS (se um dia sair do RDS) quanto para dar a qualquer pessoa autorizada uma cópia dos dados sem precisar restaurar um snapshot inteiro. Por isso ele entra como uma segunda camada mesmo com RDS.

## 3. Plano por cenário

### 3.1 Cenário A — RDS (caminho recomendado)

Duas camadas, para não depender de um único mecanismo:

**Camada 1 — nativa do RDS (primária, cobre a maior parte dos casos)**
- Backups automáticos ligados, retenção mínima de 7 dias (14 recomendado em produção, custo baixo no tamanho atual do banco).
- Snapshot manual antes de cada `migrate` em produção (já previsto na Fase 5 do plano de subida).
- *Deletion protection* ligada (impede `DROP` da instância por engano).
- Janela de manutenção e de backup configuradas fora do horário de uso (rotas rodam de dia; a Fase 7 do plano de subida já cita isso).

**Camada 2 — lógica, portável (segurança adicional, independe da AWS/RDS)**
- `CronJob` no cluster rodando `pg_dump --format=custom` contra o RDS (usando o papel `rotacerta_owner` ou um papel só de leitura dedicado a isso — ver seção 5), comprimido, enviado a um bucket S3 dedicado.
- Retenção do S3 por *lifecycle policy*: diário por 14 dias, semanal por 8 semanas, mensal por 6 meses (ajustável — ver seção 7, é uma decisão de negócio, não técnica).
- Versionamento do bucket ligado (proteção extra contra sobrescrita/exclusão acidental do próprio backup).

### 3.2 Cenário B — Postgres dentro do cluster (se a Fase 2 escolher esta opção)

**Camada 1 — nativa do Postgres (primária)**
- WAL archiving contínuo + `pg_basebackup` periódico, via `pgBackRest` (maduro, com suporte a repositório S3 nativo, paralelismo e verificação de integridade) ou `wal-g`. Dá PITR real, do mesmo jeito que o RDS dá.
- Repositório em S3, com o mesmo esquema de retenção da seção 3.1.

**Camada 2 — imagem, como complemento (não substitui a camada 1)**
- `VolumeSnapshot` (CSI) do PVC onde vive o `PGDATA`, ou EBS snapshot via AWS Backup, tirado **depois** de `pg_backup_start()`/`pg_backup_stop()` (ou de um hook do `pgBackRest`) para garantir consistência — nunca um snapshot "a frio" do volume em uso.
- Serve como restauração rápida de todo o volume em caso de perda total do nó/PV; a `pgBackRest`/WAL archiving continua sendo o que garante PITR granular.

## 4. Runbook de restauração e cadência de teste

Backup que nunca foi restaurado não é backup, é uma suposição. O plano de subida já cita "teste de restauração" na Fase 7 em uma linha; aqui o procedimento:

1. **RDS (Cenário A):** restaurar o snapshot mais recente (ou um ponto via PITR) numa instância temporária (`rotacerta-restore-teste`), rodar `sql/02_verificacao.sql` contra ela, comparar contagens de tabelas/registros-chave com a produção, depois **excluir a instância temporária**.
2. **`pg_dump` (Camada 2, ambos os cenários):** `pg_restore` do dump mais recente num banco local ou temporário, mesma verificação.
3. **Cenário B (`pgBackRest`):** `pgbackrest restore` para um novo `PGDATA` de teste, subir uma instância temporária do Postgres apontando para ele, mesma verificação.
4. **Cadência:** mensal, num ambiente separado (não em produção). Registrar o resultado (passou/falhou, tempo gasto) — isso também mede o **RTO** real, não o teórico.

## 5. Segurança e permissões

- O papel usado pelo `pg_dump`/`pgBackRest` **não** deve ser `rotacerta_app` (que só tem DML nas tabelas da aplicação) nem precisa ser `rotacerta_owner` diretamente — se quiser separar responsabilidades, crie um terceiro papel `rotacerta_backup` (`LOGIN`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, com `SELECT` em todas as tabelas via `pg_read_all_data` no PostgreSQL 14+) só para isso, seguindo o padrão de `sql/01_roles_e_banco.sql`.
- O bucket S3 de backup: acesso só pela *role* IAM do `CronJob` (via IRSA, já que o cluster é `kubeadm` em EC2 — configurar OIDC provider — ou via credenciais de instância com política restrita se IRSA não estiver disponível), permissão apenas de escrita (`PutObject`) no dia a dia; leitura/restauração usa uma *role* separada, usada manualmente.
- Criptografia: SSE-KMS no bucket S3; os snapshots do RDS herdam a criptografia da instância (defina `StorageEncrypted=true` na criação, na Fase 2 — não dá para ligar depois sem recriar a instância).
- Credenciais do `pg_dump`/`pgBackRest` vêm de um `Secret` do Kubernetes, do mesmo jeito que o Secret do Django (`02-plano-de-subida-aws.md`, seção 6) — nunca hardcoded no `CronJob`.

## 6. Plano faseado

| Fase | Conteúdo | Aceite |
|------|----------|--------|
| **B0 — Decisão de cenário** | Confirmar RDS vs. in-cluster (mesma decisão D1 do plano de subida — não é uma segunda decisão, é a mesma) | D1 confirmado |
| **B1 — Camada nativa** | RDS: `BackupRetentionPeriod`, `DeletionProtection`, `StorageEncrypted` na criação da instância (Fase 2 do plano de subida). In-cluster: instalar `pgBackRest`, configurar repositório S3, primeiro `pg_basebackup` | Snapshot/backup base existe e aparece no console/`pgbackrest info` |
| **B2 — Camada lógica** | `CronJob` de `pg_dump` → S3, com retenção por *lifecycle policy* | Um `.dump` aparece no bucket após a execução agendada; `pg_restore --list` confirma que é válido |
| **B3 — Teste de restauração** | Rodar o runbook da seção 4 pela primeira vez, cronometrando | RTO medido e registrado; `sql/02_verificacao.sql` bate com produção |
| **B4 — Operação contínua** | Alarme no CloudWatch para falha de backup (RDS já expõe evento de backup; `CronJob` expõe falha via `kubectl` — considerar alerta simples via SNS a partir do `CronJob`); cadência mensal do runbook (seção 4) | Alarme testado (forçar uma falha) e primeira execução mensal registrada |

## 7. Perguntas em aberto (decisão do time, não técnica)

- **Retenção**: os números da seção 3.1 (7–14 dias no RDS, 14/8/6 no S3) são um ponto de partida razoável para o volume atual do banco (ver `01-mapa-do-banco.md`, volumetria) — confirme se há exigência de retenção maior (por exemplo, por contrato com alguma empresa cliente).
- **RTO/RPO alvo**: não foi informado um valor. Como referência para uma operação deste porte: RPO ≤ 5 min (coberto pelo PITR do RDS/WAL archiving) e RTO ≤ 1h (tempo de restaurar uma instância RDS de snapshot + rodar a verificação) são alcançáveis com o plano acima sem custo adicional relevante; ajuste se o negócio exigir algo mais agressivo (o que muda a Camada 2 — encurtar o intervalo de `pg_dump`, por exemplo).
- **DR entre regiões**: nada aqui cobre a perda da região `us-east-1` (ou a que for usada) inteira — só do banco. Se isso for um requisito, entra como uma fase B5 (cópia de snapshot/S3 cross-region), fora do escopo atual.

## 8. Rastreamento

- Atualiza `02-plano-de-subida-aws.md`: D6 passa a apontar para este documento; Fase 7 ("Alarmes… teste de restauração") passa a seguir o runbook da seção 4.
- Relacionado: `01-mapa-do-banco.md` (volumetria, para dimensionar a janela de retenção).
