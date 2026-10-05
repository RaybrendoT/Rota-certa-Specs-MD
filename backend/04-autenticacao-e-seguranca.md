# 04 — Autenticação e segurança

Fontes: `core/auth_views.py`, `core/auth_serializers.py`, `core/authentication.py`, `core/tokens.py`, `core/password_reset.py`, `core/access_passwords.py`, `core/signals.py`, `config/settings.py`.

## 1. Modelo de identidade

O projeto **não usa** o `User` do Django. A identidade é a `AccessAccount` (1:1 com `Person`).

- Autenticação DRF padrão: `core.authentication.AccessAccountJWTAuthentication` (SimpleJWT).
- `request.user` é um `AccessAccountPrincipal` com `access_account`, `person`, `role`, `id`, `is_authenticated=True`, `is_active`. O `role` é lido do banco a cada requisição (não é claim do token).
- Tokens: `AccessAccountRefreshToken` / `AccessAccountAccessToken`; claims `access_account_id` (`USER_ID_CLAIM`), `person_id`, `must_change_password`.
- Validade: access **60 min**, refresh **7 dias**; header `Authorization: Bearer <access_token>`.

## 2. Criação automática de contas (`signals.py`)

Ao salvar uma `Person` ativa (se `ACCESS_ACCOUNT_AUTO_CREATE=True`, padrão):

1. Se já existe conta, nada é criado.
2. E-mail = `Person.get_auto_email()` (`{código|licença}@{domínio da empresa}`). Sem código/licença ou e-mail já usado por outra conta ⇒ conta não criada (log de aviso).
3. Senha inicial = `ACCESS_ACCOUNT_AUTO_INITIAL_PASSWORD` se definida; senão **matrícula/licença + últimos 4 dígitos do telefone** (ex.: `101010` + `...1234` ⇒ `1010101234`).
4. `must_change_password = True`.

5. `role` = `DRIVER` se a pessoa é motorista, senão `EMPLOYEE`. Se o tipo da pessoa mudar depois, o perfil é reconciliado (`sync_access_account_role_for_person`): motorista→funcionário vira `EMPLOYEE`; gestor→motorista vira `DRIVER` (perde o acesso de gestor).

Sincronização de e-mail (`ACCESS_ACCOUNT_SYNC_EMAIL=True`, padrão): ao salvar `Person` ou `Company`, o e-mail da conta é atualizado para o e-mail automático, exceto se houver colisão.

## 3. Endpoints

Públicos (`AllowAny`, sem autenticação), exceto `me` e `change-password`.

### `POST auth/login/`
Entrada: `{ "email", "password" }`. Saída 200:
```json
{ "access_token": "...", "refresh_token": "...", "must_change_password": true,
  "person": { "id": 1, "name": "...", "type": "DRIVER|EMPLOYEE", "role": "DRIVER|EMPLOYEE|MANAGER",
              "email": "...", "company_id": 1, "company_name": "..." } }
```
Regras:
- E-mail é normalizado (trim + minúsculas).
- Conta bloqueada (`blocked_until > agora`) ⇒ 401 "Conta temporariamente bloqueada." (`account_locked`).
- Conta ou pessoa inativa, e-mail inexistente ou senha incorreta ⇒ 401 "Credenciais inválidas."
- Senha incorreta incrementa `failed_login_attempts`; ao atingir **5** (`ACCESS_ACCOUNT_MAX_FAILED_ATTEMPTS`) bloqueia por **30 min** (`ACCESS_ACCOUNT_LOCKOUT_MINUTES`).
- Sucesso zera tentativas/bloqueio e grava `last_login`.

### `GET auth/me/` (autenticado)
Saída 200: `{ "must_change_password": bool, "person": { …mesmo formato do login, com `role` } }`, lido do banco. O painel usa para revalidar perfil e obrigatoriedade de troca de senha ao recarregar a página.

### `POST auth/refresh/`
Entrada: `{ "refresh": "<refresh_token>" }`. Saída: `{ "access_token" }`. Valida que a conta e a pessoa continuam ativas. Não rotaciona o refresh.

### `POST auth/verify/`
Entrada: `{ "token": "..." }` (SimpleJWT `TokenVerifyView`). 200 com corpo vazio se válido.

### `POST auth/change-password/` (autenticado)
Entrada: `{ "current_password", "new_password" }`. Regras: senha atual correta; nova ≠ atual; nova passa nos validadores Django (`AUTH_PASSWORD_VALIDATORS`). Efeito: atualiza hash, `must_change_password=False`, devolve novo par de tokens e `person` (mesmo formato do login).

### Redefinição de senha por código (OTP, sem envio de e-mail)
Identificador: **exatamente um** entre `email` e `phone` (telefone comparado somente por dígitos, mín. 8).

| Endpoint | Entrada | Comportamento |
|----------|---------|---------------|
| `POST auth/password-reset/request/` | `email` ou `phone` | Sempre 200 `{ "status": "ok" }` (não revela existência). Gera OTP numérico (`PASSWORD_RESET_CODE_LENGTH`=6, faixa 4–12), TTL `PASSWORD_RESET_CODE_TTL_MINUTES`=15. Se `PASSWORD_RESET_RETURN_CODE_IN_RESPONSE` (padrão = `DEBUG`) devolve `verificationCode` no corpo |
| `POST auth/password-reset/verify/` | identificador + `code` | 200 `{ "valid": true }` ou 400 `{ "valid": false, "detail": "Código inválido ou expirado." }` |
| `POST auth/password-reset/reset/` | identificador + `code` + `new_password` | Valida OTP e a nova senha; grava hash, limpa OTP, zera tentativas e bloqueio; `must_change_password = PASSWORD_RESET_FORCE_MUST_CHANGE_PASSWORD` (padrão `False`) |

O OTP é guardado como hash; após uso fica marcado como usado.

## 4. Autorização

| Componente | Regra |
|------------|-------|
| `IsManager` | `request.user.role == MANAGER` |
| `IsDriver` | `request.user.role == DRIVER` |
| `IsManagerOrDriver` | Gestor ou motorista; o viewset restringe o motorista às próprias rotas (`route.vehicle.driver == person`) |
| `DEFAULT_PERMISSION_CLASSES` | `IsAuthenticated` (nada é público, exceto `auth/login`, `refresh`, `verify` e `password-reset/*`, que declaram `AllowAny`) |
| `BaseViewSet` (CRUD administrativo) | `IsAuthenticated` + `IsManager` |
| `route-events/`, `route-passengers/`, `routes/{id}/events/` | `IsManagerOrDriver` em ações limitadas, com escopo de dono (ver `03-api-rest.md` §4) |
| `routes/my-routes`, `driver-detail`, `navigation` | `IsAuthenticated` + `IsDriver` |

Matriz completa por recurso em `03-api-rest.md` §4. O perfil (`AccessAccount.role`) e como criar o primeiro gestor: `../database/03-migrations-e-superuser.md` §2.1.

> Ainda em aberto (review 11): `must_change_password` não é imposto no servidor (A3), refresh vira Bearer (A1) e sessões não expiram na troca de senha (A4). O painel Angular impõe a troca de senha só no cliente.

## 5. Outras configurações de segurança

| Item | Estado atual |
|------|--------------|
| CORS | `CORS_ALLOW_ALL_ORIGINS = True` |
| `CSRF_TRUSTED_ORIGINS` | `http://localhost:4200` |
| `DEBUG` | via env, padrão `False`; com `DEBUG=True`, `ALLOWED_HOSTS=["*"]` |
| `SECRET_KEY` | via env; padrão inseguro `insecure-key-change-me` |
| Throttling | `anon` 100/h, `user` 1000/h |
| Hash de senha | padrão Django (`make_password`) |
