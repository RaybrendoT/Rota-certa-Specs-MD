# 09 — Configuração e execução

## 1. Backend

### Variáveis de ambiente (`.env`, lidas com `python-decouple`)

| Variável | Padrão | Uso |
|----------|--------|-----|
| `DEBUG` | `False` | Modo debug. Com `True`, `ALLOWED_HOSTS` vira `["*"]` e o código de reset de senha é devolvido na resposta |
| `SECRET_KEY` | `insecure-key-change-me` | Chave do Django (**definir em qualquer ambiente real**) |
| `ALLOWED_HOSTS` | `localhost,127.0.0.1,0.0.0.0` | Lista separada por vírgula |
| `DATABASE_URL` | **obrigatória, sem padrão** | `postgres://user:senha@host:5432/db[?sslmode=...&conn_max_age=...]`. PostgreSQL é o único motor suportado: ausente ou com outro esquema, a aplicação falha ao subir (`RuntimeError`/`ValueError`) — ver `database/04-postgres-exclusivo.md`, aplicado nesta sessão |
| `GOOGLE_MAPS_API_KEY` | vazio | Necessária para `routes/{id}/navigation/` (sem ela retorna 503) |
| `GOOGLE_ROUTES_API_URL` | `https://routes.googleapis.com/directions/v2:computeRoutes` | Endpoint do Google Routes |
| `ACCESS_ACCOUNT_AUTO_CREATE` | `True` | Cria conta de acesso ao salvar `Person` |
| `ACCESS_ACCOUNT_AUTO_INITIAL_PASSWORD` | vazio | Senha inicial fixa; vazio ⇒ matrícula/licença + 4 últimos dígitos do telefone |
| `ACCESS_ACCOUNT_SYNC_EMAIL` | `True` | Sincroniza e-mail da conta com pessoa/empresa |
| `PASSWORD_RESET_CODE_TTL_MINUTES` | `15` | Validade do OTP |
| `PASSWORD_RESET_CODE_LENGTH` | `6` | Dígitos do OTP (limitado a 4–12 no código) |
| `PASSWORD_RESET_RETURN_CODE_IN_RESPONSE` | valor de `DEBUG` | Devolve o OTP no corpo da resposta (só para desenvolvimento/testes) |
| `PASSWORD_RESET_FORCE_MUST_CHANGE_PASSWORD` | `False` | Exige nova troca de senha após o reset |

Constantes fixas em `settings.py`: `ACCESS_ACCOUNT_MAX_FAILED_ATTEMPTS = 5`, `ACCESS_ACCOUNT_LOCKOUT_MINUTES = 30`, JWT access 60 min / refresh 7 dias.

O arquivo `.env.example` do repositório mostra `DEBUG`, `SECRET_KEY`, `ALLOWED_HOSTS`, `DATABASE_URL`, `GOOGLE_MAPS_API_KEY` e `GOOGLE_ROUTES_API_URL`.

### Execução local

```bash
cd "Rota-certa-2026 (Backend Django)"
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt                        # ver observação sobre a codificação do arquivo
cp .env.example .env                                   # ajustar valores
python manage.py migrate
python manage.py seed_manaus_demo                      # opcional: dados de demonstração
python manage.py runserver 0.0.0.0:8000
```

- API em `http://localhost:8000/api/`; admin Django em `/admin/` (criar usuário com `createsuperuser`).
- `requirements.txt` está salvo em **UTF-16 LE**; se o `pip` falhar ao lê-lo, converter para UTF-8 (`iconv -f utf-16 -t utf-8`).
- **PostgreSQL é obrigatório mesmo em desenvolvimento local** (`docker run --name rotacerta-pg -e POSTGRES_PASSWORD=... -p 5432:5432 -d postgres:16`, por exemplo) — o fallback para SQLite foi removido do código (`database/04-postgres-exclusivo.md`).

## 2. Frontend

```bash
cd "Rota-certa-2026 (Frontend Angular)"
npm install
# editar src/assets/config/config.json → { "apiBaseUrl": "http://localhost:8000/api" }
npm start            # ng serve, http://localhost:4200
npm run build        # saída em dist/
npm test             # Karma + Jasmine
```

- `config.json` é carregado em tempo de execução (`APP_INITIALIZER`), então pode ser trocado no ambiente publicado **sem recompilar**.
- Origem `http://localhost:4200` já consta em `CSRF_TRUSTED_ORIGINS`; o CORS do backend está aberto a qualquer origem.

## 3. Integração entre as camadas em desenvolvimento

1. Subir o backend em `0.0.0.0:8000` (para dispositivos/emulador na mesma rede).
2. Apontar `apiBaseUrl` do frontend para o IP/host do backend com sufixo `/api`.
3. Não há proxy de desenvolvimento configurado no Angular; a comunicação depende de CORS.

## 4. Banco de dados

- Migrações em `core/migrations` (`0001_initial` a `0007_create_initial_superuser`; `0006_access_account_role` adiciona `AccessAccount.role`/MANAGER).
- Dados de demonstração: `seed_manaus_demo` (idempotência não verificada nestas specs).
- O arquivo `db.sqlite3` do repositório está vazio (0 bytes); há também `core_data.json` e `data.json` na raiz do backend (fixtures/exports).
