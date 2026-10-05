# PostgreSQL exclusivo — remoção do fallback para SQLite

## 1. A regra de negócio identificada

O código hoje decide o motor do banco em tempo de execução, a partir da variável `DATABASE_URL`. Está inteira em `config/settings.py`:

```python
def build_database_config(database_url: str):
    if not database_url or database_url.startswith("sqlite"):
        parsed = urlparse(database_url or "")
        db_name = parsed.path.lstrip("/") if parsed.path else "db.sqlite3"
        return {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / db_name,
        }

    parsed = urlparse(database_url)
    if parsed.scheme not in {"postgres", "postgresql"}:
        raise ValueError(f"Unsupported DATABASE_URL scheme: {parsed.scheme}")

    return {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": unquote(parsed.path.lstrip("/")),
        "USER": unquote(parsed.username or ""),
        "PASSWORD": unquote(parsed.password or ""),
        "HOST": parsed.hostname or "localhost",
        "PORT": parsed.port or 5432,
    }


DATABASES = {
    "default": build_database_config(
        config("DATABASE_URL", default="sqlite:///db.sqlite3")
    )
}
```

Três pontos, juntos, formam a "regra de troca":

| Onde | O que faz |
|------|-----------|
| `build_database_config` | Se `DATABASE_URL` está vazia **ou** começa com `sqlite`, monta config de SQLite. Só cai no ramo PostgreSQL se o esquema for `postgres`/`postgresql`; qualquer outro esquema levanta `ValueError` — mas a ausência da variável não é tratada como erro, é tratada como "use SQLite" |
| `config("DATABASE_URL", default="sqlite:///db.sqlite3")` | Se a variável de ambiente **não existir em absoluto** (não só vazia), o padrão já é uma URL de SQLite |
| `.env.example` | Comentário explícito ensinando a troca: `# Para voltar ao SQLite local: DATABASE_URL=sqlite:///db.sqlite3` |

Evidência de que já foi usado assim: `.gitignore` ignora `db.sqlite3`/`db.sqlite3-journal`, e o arquivo `db.sqlite3` existe no repositório (vazio hoje, 0 bytes — não está em uso agora, mas a capacidade de trocar continua ativa no código).

Não há nenhuma outra dependência de SQLite no projeto: nenhuma feature, migração ou teste depende de `django.db.backends.sqlite3` especificamente; é puramente a configuração de conexão. Isso significa que remover o ramo é seguro do ponto de vista funcional — o projeto já roda 100% sobre PostgreSQL sempre que `DATABASE_URL` é uma URL `postgres://`.

## 2. Por que isso é um risco (não só uma preferência)

Não é o uso do SQLite em si que é o problema — é o **fallback silencioso**:

1. **Ausência de variável não é tratada como erro.** Se o Secret/ConfigMap do Kubernetes tiver o nome errado, não for montado, ou a chave `DATABASE_URL` for esquecida numa migração de `.env` para Secret, a aplicação **não falha ao subir** — ela silenciosamente escreve em `db.sqlite3` dentro do próprio container.
2. **SQLite em container é descartável e não compartilhado.** Cada Pod do Deployment tem seu próprio filesystem efêmero: duas réplicas gravariam em dois bancos diferentes, e um restart apaga tudo. Isso corrompe dados de forma silenciosa (sem erro, sem log óbvio) em vez de simplesmente não subir.
3. **É o oposto do que se quer em produção.** O objetivo é falhar rápido e alto (fail fast, fail loud) quando a configuração de banco está errada, não continuar rodando contra um banco errado.
4. **Reforça P-04** (`database/02-plano-de-subida-aws.md`, Fase 0): a mesma função também ignora `sslmode` e `CONN_MAX_AGE` da URL — os dois problemas vivem na mesma função e no mesmo commit de correção.

Por isso este achado entra no backlog como **S-09** em `10-lacunas-e-melhorias.md` (seção de Segurança, mesma família de S-03 — "falhar na inicialização sem `SECRET_KEY`").

## 3. Decisão

Manter **PostgreSQL único e exclusivo**:

- `DATABASE_URL` passa a ser **obrigatória** (sem valor padrão) e deve ter esquema `postgres://` ou `postgresql://`.
- Qualquer outra coisa — variável ausente, vazia, ou com esquema `sqlite`/outro — faz a aplicação **recusar subir**, com uma mensagem de erro clara (não um `KeyError`/`AttributeError` genérico).
- De caminho, corrige P-04: aceita `sslmode` e `conn_max_age` como parâmetros de query da própria `DATABASE_URL`, em vez de deixá-los implícitos.
- O suporte a SQLite no `django.db.backends.sqlite3` é parte do próprio Django (não é uma dependência do `requirements.txt`), então não há pacote para remover — só o branch de código em `settings.py`.

## 4. Código proposto (substitui a função e o `DATABASES` em `config/settings.py`)

```python
from urllib.parse import parse_qs, unquote, urlparse

# ...

def build_database_config(database_url: str):
    """
    PostgreSQL é o único motor suportado. Não existe fallback para SQLite:
    a ausência ou um esquema diferente de DATABASE_URL impede a subida da
    aplicação (fail fast) em vez de gravar silenciosamente num arquivo
    local descartável.
    """
    if not database_url:
        raise RuntimeError(
            "DATABASE_URL não definida. Este projeto usa PostgreSQL "
            "exclusivamente — não há mais fallback para SQLite. "
            "Defina, por exemplo: "
            "postgres://usuario:senha@host:5432/nome_do_banco?sslmode=require"
        )

    parsed = urlparse(database_url)
    if parsed.scheme not in {"postgres", "postgresql"}:
        raise ValueError(
            f"DATABASE_URL deve usar o esquema postgres:// ou postgresql:// "
            f"(recebido: {parsed.scheme!r}). SQLite não é suportado neste projeto."
        )

    query = parse_qs(parsed.query)

    options = {}
    sslmode = query.get("sslmode", [None])[0]
    if sslmode:
        options["sslmode"] = sslmode

    conn_max_age = query.get("conn_max_age", [None])[0]

    db_config = {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": unquote(parsed.path.lstrip("/")),
        "USER": unquote(parsed.username or ""),
        "PASSWORD": unquote(parsed.password or ""),
        "HOST": parsed.hostname or "localhost",
        "PORT": parsed.port or 5432,
        "CONN_MAX_AGE": int(conn_max_age) if conn_max_age else 60,
    }
    if options:
        db_config["OPTIONS"] = options

    return db_config


# Database
# https://docs.djangoproject.com/en/6.0/ref/settings/#databases
DATABASES = {
    "default": build_database_config(config("DATABASE_URL", default=""))
}
```

Notas sobre as escolhas:

- `default=""` no `config(...)` (em vez de remover o argumento) para que a mensagem de erro venha da própria `build_database_config` — com o texto explicando o porquê — em vez de um erro genérico do `python-decouple`.
- `CONN_MAX_AGE=60` como padrão quando `conn_max_age` não vier na URL: conexões persistentes por 60s reduzem o custo de abrir conexão a cada request; ajustável por ambiente (ex.: `?conn_max_age=0` para desabilitar, útil atrás de um PgBouncer em modo transaction).
- `sslmode` só entra em `OPTIONS` se vier explícito na URL — no RDS, recomenda-se `sslmode=require` (ou `verify-full` com o certificado da AWS) na `DATABASE_URL` do Secret.

## 5. `.env.example`

Remover o comentário que ensina a trocar para SQLite e deixar explícito que só PostgreSQL é aceito:

```diff
  DEBUG=True
  SECRET_KEY=seu-valor-aqui
  ALLOWED_HOSTS=localhost,127.0.0.1
- DATABASE_URL=postgres://postgres:123456@localhost:5432/route_monitoring
- # Para voltar ao SQLite local:
- # DATABASE_URL=sqlite:///db.sqlite3
+ # Obrigatória. Só PostgreSQL é suportado (sem fallback para SQLite).
+ DATABASE_URL=postgres://postgres:123456@localhost:5432/route_monitoring?sslmode=disable
  GOOGLE_MAPS_API_KEY=coloque-sua-chave-aqui
  GOOGLE_ROUTES_API_URL=https://routes.googleapis.com/directions/v2:computeRoutes
```

(A troca de `GOOGLE_MAPS_API_KEY` para um placeholder já está registrada em S-02; incluída aqui só para lembrar que o `.env.example` tem os dois ajustes pendentes.)

## 6. O que **não** muda

- **`.gitignore`**: mantenha as entradas `db.sqlite3` e `db.sqlite3-journal`. Não custa nada tê-las, e protegem contra alguém commitar um arquivo local por engano caso rode algo fora do fluxo padrão (um teste unitário isolado, por exemplo, que normalmente usa um banco em memória e nem chega a tocar `settings.py`).
- **`requirements.txt`**: nada a remover — `psycopg2-binary` já é a única dependência de banco declarada; o backend SQLite é parte do Django, não um pacote.
- **Desenvolvimento local**: passa a exigir PostgreSQL local (ou um container `docker run postgres`) para qualquer pessoa rodar o backend, inclusive para `runserver`/testes manuais. Isso é uma mudança real de fluxo de trabalho local — ver checklist abaixo.

## 7. Testes propostos

Cobre os quatro comportamentos da função nova (formato compatível com os testes já propostos em `03-migrations-e-superuser.md`, para colocar em `core/tests.py` quando o backend tiver suíte de testes — ver B-11):

```python
from django.test import SimpleTestCase
from config.settings import build_database_config


class BuildDatabaseConfigTests(SimpleTestCase):
    def test_sem_database_url_falha(self):
        with self.assertRaises(RuntimeError):
            build_database_config("")

    def test_sqlite_nao_e_mais_aceito(self):
        with self.assertRaises(ValueError):
            build_database_config("sqlite:///db.sqlite3")

    def test_esquema_invalido_falha(self):
        with self.assertRaises(ValueError):
            build_database_config("mysql://user:pw@host:3306/db")

    def test_postgres_valido(self):
        cfg = build_database_config(
            "postgres://user:pw@host:5432/rotacerta?sslmode=require&conn_max_age=30"
        )
        self.assertEqual(cfg["ENGINE"], "django.db.backends.postgresql")
        self.assertEqual(cfg["HOST"], "host")
        self.assertEqual(cfg["OPTIONS"], {"sslmode": "require"})
        self.assertEqual(cfg["CONN_MAX_AGE"], 30)

    def test_conn_max_age_padrao_60(self):
        cfg = build_database_config("postgres://user:pw@host:5432/rotacerta")
        self.assertEqual(cfg["CONN_MAX_AGE"], 60)
        self.assertNotIn("OPTIONS", cfg)
```

Não executados aqui pelo mesmo motivo dos demais testes deste conjunto de specs (sem Django instalável neste ambiente — ver `11-code-review-backend.md`, "Método e limites"); a lógica foi conferida lendo a função linha a linha e simulando os quatro ramos manualmente.

## 8. Checklist de aplicação

1. ~~Substituir `build_database_config`/`DATABASES` em `config/settings.py` pelo código da seção 4~~ — **aplicado**.
2. ~~Atualizar `.env.example` conforme a seção 5~~ — **aplicado**.
3. Garantir PostgreSQL local (`docker run --name rotacerta-pg -e POSTGRES_PASSWORD=... -p 5432:5432 -d postgres:16`, por exemplo) antes de rodar `manage.py runserver`/testes — a partir de agora `db.sqlite3` deixa de ser uma opção mesmo em desenvolvimento. **Pendente de conferência local** (não há Django rodando nesta sessão para validar).
4. Rodar os testes da seção 7. **Pendente** (mesmo motivo).
5. Confirmar que o `.env` real (não versionado) de cada ambiente (dev, CI, AWS) tem `DATABASE_URL` no formato `postgres://...`; na AWS ela vem do Secret (ver `03-migrations-e-superuser.md` e o Secret listado em `02-plano-de-subida-aws.md`, seção 6). **Pendente**.
6. ~~Marcar P-04 (`02-plano-de-subida-aws.md`) como resolvido por este documento~~ — **feito**.

## 9. Rastreamento

- Backlog: `10-lacunas-e-melhorias.md`, item **S-09** (marcar como resolvido).
- Relacionado: `02-plano-de-subida-aws.md`, Fase 0, **P-04** (resolvido).
- **Aplicado** ao repositório real nesta sessão: `config/settings.py` e `.env.example`. Falta rodar o backend contra um PostgreSQL de verdade (item 3 do checklist) — não há Django disponível neste ambiente para validar (mesma limitação de `11-code-review-backend.md`, "Método e limites").
