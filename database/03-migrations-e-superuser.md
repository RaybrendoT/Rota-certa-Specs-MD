# Migrações e superusuário

## 1. Estado das migrações

| Migração | Conteúdo | Situação |
|----------|----------|----------|
| `0001_initial` | Company, Person, Address, MeetingPoint, Route, RouteEvent, Schedule, Vehicle, RoutePassenger | existente |
| `0002_access_account` | AccessAccount | existente |
| `0003_company_email_domain` | `Company.email_domain` | existente |
| `0004_access_account_password_reset` | colunas do OTP em AccessAccount | existente |
| `0005_driver_route_stops` | `Route.vehicle`, `RoutePassenger.boarding_status` e `route_stop`, tabela RouteStop | existente |
| `0006_access_account_role` | `AccessAccount.role` (DRIVER/EMPLOYEE/MANAGER), backfill por `person.type` | existente — surgiu depois do mapeamento inicial (`01-mapa-do-banco.md`), ver nota e §2 |
| **`0007_create_initial_superuser`** | Cria o superusuário do Django admin | **aplicada nesta sessão** (copiada para `core/migrations/`) |
| `0008+` | Endurecimento do esquema (seção 5) | proposta, não incluída |

**Nota sobre a renumeração.** Esta migração foi escrita originalmente como `0006_create_initial_superuser`, dependendo de `0005_driver_route_stops` — a última migração que existia quando `01-mapa-do-banco.md` foi feito. Nesse meio-tempo o repositório ganhou `0006_access_account_role` (o perfil `MANAGER` — ver §2), então ela foi renumerada para `0007` e passou a depender de `0006_access_account_role`. Não lê nem altera o campo `role`; a ordem entre as duas não afeta o comportamento de nenhuma.

A cadeia é linear e coerente com `models.py` pelo que a leitura mostra. Antes da subida, confirme com `python manage.py makemigrations --check --dry-run` (não foi possível rodar aqui): deve responder "No changes detected".

## 2. Três coisas chamadas "superusuário" (e a que apareceu no meio do caminho)

| O que | Onde vive | Para quê | Quem cria |
|-------|-----------|----------|-----------|
| **Superusuário do Django admin** | tabela `auth_user` | Entrar em `/admin/` | **Migração 0007** (este documento) |
| SUPERUSER do PostgreSQL (`postgres`) / `rds_superuser` do RDS | papéis do servidor | Administrar o servidor, criar papéis e banco | Provisionamento; usado só em `sql/01_roles_e_banco.sql` e **nunca** pela aplicação |
| Administrador **da API/frontend** (`AccessAccount.role = MANAGER`) | `core_accessaccount` | Gerir cadastros pelo app/frontend | Aplicação — `0006_access_account_role` |

A lacuna registrada aqui antes ("não há perfil de gestor") **já foi resolvida no código**: `AccessAccount` ganhou o campo `role` (`DRIVER`/`EMPLOYEE`/`MANAGER`), e `core/permissions.py` tem `IsManager`/`IsDriver`/`IsManagerOrDriver`. O `settings.py` também não usa mais `AllowAny` por padrão — `DEFAULT_PERMISSION_CLASSES` já exige autenticação (o achado S-01 do backlog está, na prática, resolvido). Isso aconteceu fora desta sessão de specs; `10-lacunas-e-melhorias.md` e `11-code-review-backend.md` ainda descrevem o estado anterior (sem MANAGER, API pública) e não foram reauditados linha a linha contra essa mudança — trate as referências a S-01/A2 nesses documentos como desatualizadas até uma nova passada.

O superusuário do admin continua sendo uma coisa **diferente** do MANAGER: um só entra em `/admin/` (Django puro), o outro é quem a API reconhece como gestor via JWT. Não há sobreposição nem conflito entre os dois.

Observação: `core/admin.py` não registra nenhum model. O superusuário vai ver só "Usuários" e "Grupos" até você registrar as entidades do domínio (opcional, P-10).

## 3. A migração 0007

Arquivo: `database/migrations/0007_create_initial_superuser.py` — **já copiado** para `core/migrations/0007_create_initial_superuser.py` no repositório real.

**Comportamento**

| Situação | Resultado |
|----------|-----------|
| `DJANGO_SUPERUSER_USERNAME` ou `DJANGO_SUPERUSER_PASSWORD` ausentes | Não faz nada (desenvolvimento local e testes) |
| Senha com menos de 12 caracteres | Falha a migração com mensagem clara (o `migrate` para) |
| Usuário já existe | Não altera nada (idempotente) |
| Caso contrário | Cria `auth_user` com `is_staff=True`, `is_superuser=True`, `is_active=True`, senha em hash PBKDF2 |
| Reverse (`migrate core 0006`) | Não apaga o superusuário |

**Decisões de projeto**
- Sem senha padrão no código: a credencial vem de variáveis de ambiente (os mesmos nomes do `createsuperuser --noinput` do Django).
- Usa o model histórico (`apps.get_model("auth", "User")`) e `make_password`, como recomenda o Django para migrações de dados; não importa o model real.
- Depende de `("auth", "0012_alter_user_first_name_max_length")` para que `auth_user` esteja no formato final antes do `INSERT`, e de `core.0006_access_account_role` para manter a cadeia linear.
- A senha não é registrada em log.
- Assume o `auth.User` padrão (é o caso: não há `AUTH_USER_MODEL` customizado).

**Limites**
- Roda uma vez, quando a migração é aplicada. Mudar a senha depois não é feito reaplicando a migração: use `python manage.py changepassword <usuario>` ou o admin.
- Se o banco já tiver aplicado 0007 sem as variáveis, ela ficou como "aplicada" sem criar ninguém. Nesse caso crie o usuário com `createsuperuser` (seção 4).

**Uso local (teste antes da AWS)**
```bash
export DJANGO_SUPERUSER_USERNAME=admin
export DJANGO_SUPERUSER_EMAIL=admin@exemplo.com
export DJANGO_SUPERUSER_PASSWORD='uma-senha-forte-com-12+'
python manage.py migrate
python manage.py shell -c "from django.contrib.auth import get_user_model as g; print(g().objects.filter(is_superuser=True).values('username','is_staff'))"
```

## 4. Alternativas

| Opção | Quando usar |
|-------|-------------|
| **Migração 0007** (recomendada, pedido, já aplicada) | Primeira subida automática: o `migrate` já deixa o admin pronto |
| `python manage.py createsuperuser --noinput` num Job | Se o usuário foi perdido ou a 0007 rodou sem variáveis. Falha se o usuário já existe, então não serve para rotação |
| Comando `ensure_superuser` próprio (criar/atualizar senha, idempotente) | Se quiser rotacionar senha por Job sem acesso interativo |
| Nenhum superusuário automático + `kubectl exec ... createsuperuser` | Se preferir que a senha nunca passe por Secret |

## 5. Migrações de endurecimento propostas (0008+)

Não fazem parte da primeira subida: exigem mudanças no código e, se já houver dados, verificação de duplicados antes de criar constraints. Numeração indicativa.

| ID | Mudança | Motivo | Pré-verificação (deve retornar 0 linhas) |
|----|---------|--------|-------------------------------------------|
| H1 | `UniqueConstraint(company, employee_code)` onde `type='EMPLOYEE'` e `is_active` | Evitar login duplicado/sem conta (review A5) | `SELECT company_id, employee_code, count(*) FROM core_person WHERE type='EMPLOYEE' AND is_active GROUP BY 1,2 HAVING count(*)>1;` |
| H2 | `UniqueConstraint(company, license_number)` onde `type='DRIVER'` e `is_active` | Idem para motoristas | Mesma consulta com `license_number` e `type='DRIVER'` |
| H3 | `AccessAccount.token_version` (integer, default 0) | Invalidar sessões ao trocar senha (review A4) | — |
| H4 | `AccessAccount.password_reset_attempts` (smallint, default 0) | Limitar tentativas do OTP (review A6) | — |
| H5 | `CheckConstraint` de latitude/longitude em `RouteEvent` e `Address` (±90 / ±180) e `capacity > 0` em `Vehicle` | O banco aceita valores fora da faixa | `SELECT id FROM core_routeevent WHERE latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180;` |
| H6 | `Index(route, -timestamp)` em `RouteEvent`; remover `Index(person, route)` redundante de `RoutePassenger` | Consulta por rota ordenada; índice duplicado | — |
| H7 | (a decidir) vínculo `Schedule` → `Route` | Hoje horário não pertence à rota | — |

Regras para essas migrações em produção: snapshot antes; em tabelas grandes usar `AddIndexConcurrently` (só `RouteEvent` pode crescer); `CheckConstraint` com `NOT VALID` seguido de validação se a tabela for grande. No volume atual isso é dispensável.

## 6. Teste da migração (para o `core/tests.py`)

Chama a função da migração diretamente, sem tocar em variáveis de ambiente reais:

```python
import importlib
import os
from unittest import mock

from django.apps import apps as django_apps
from django.contrib.auth import get_user_model
from django.db import connection
from django.test import TestCase

mig = importlib.import_module("core.migrations.0007_create_initial_superuser")


class _SchemaEditor:            # só precisa expor .connection
    connection = connection


class InitialSuperuserMigrationTests(TestCase):
    ENV = {
        "DJANGO_SUPERUSER_USERNAME": "admin-teste",
        "DJANGO_SUPERUSER_PASSWORD": "senha-longa-de-teste-123",
        "DJANGO_SUPERUSER_EMAIL": "admin@exemplo.com",
    }

    def _run(self, env):
        with mock.patch.dict(os.environ, env, clear=False):
            mig.create_initial_superuser(django_apps, _SchemaEditor())

    def test_sem_variaveis_nao_cria_nada(self):
        for k in self.ENV:
            os.environ.pop(k, None)
        self._run({})
        self.assertFalse(get_user_model().objects.filter(username="admin-teste").exists())

    def test_cria_superusuario_com_senha_em_hash(self):
        self._run(self.ENV)
        u = get_user_model().objects.get(username="admin-teste")
        self.assertTrue(u.is_superuser and u.is_staff and u.is_active)
        self.assertNotEqual(u.password, self.ENV["DJANGO_SUPERUSER_PASSWORD"])
        self.assertTrue(u.check_password(self.ENV["DJANGO_SUPERUSER_PASSWORD"]))

    def test_idempotente(self):
        self._run(self.ENV)
        self._run({**self.ENV, "DJANGO_SUPERUSER_PASSWORD": "outra-senha-longa-456"})
        self.assertEqual(get_user_model().objects.filter(username="admin-teste").count(), 1)
        self.assertTrue(get_user_model().objects.get(username="admin-teste")
                        .check_password(self.ENV["DJANGO_SUPERUSER_PASSWORD"]))

    def test_senha_curta_falha(self):
        with self.assertRaises(RuntimeError):
            self._run({**self.ENV, "DJANGO_SUPERUSER_PASSWORD": "curta"})
```

O nome do módulo começa com número, por isso o `importlib.import_module`. Estes testes **não foram executados** aqui (sem Django instalado); a lógica da função foi conferida com um Django simulado nos quatro casos (sem variáveis, senha curta, criação, idempotência).

## 7. Checklist de aplicação

1. ~~Copiar o arquivo da 0007 para `core/migrations/`~~ — feito nesta sessão.
2. Rodar `makemigrations --check --dry-run` e os testes acima.
3. Testar localmente com as variáveis (seção 3).
4. Na AWS: variáveis só no Job `migrate`; verificar com `sql/02_verificacao.sql` (consulta 6).
5. Entrar em `/admin/`, trocar a senha e remover o Secret `django-superuser`.
