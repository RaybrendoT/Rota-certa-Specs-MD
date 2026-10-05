# 11 — Code review do backend (foco: autenticação e redundâncias)

Contexto: o backend recebeu ajustes de autenticação durante o desenvolvimento do app Flutter e agora servirá um app Kotlin. Esta revisão procura (1) conflitos e brechas na autenticação e (2) redundâncias/código morto, para limpar antes de congelar o contrato com o Kotlin.

**Método e limites.** Revisão estática de todo o `core/` e `config/settings.py`, mais migrações, comandos de gestão e arquivos soltos. Não foi possível executar o projeto neste ambiente (o índice de pacotes Python está bloqueado pela política de rede), então nada abaixo foi rodado. Os itens **A1** e **A4** dependem do comportamento do SimpleJWT 5.5.1 conhecido pela biblioteca; a seção 5 traz um teste curto para confirmá-los. Complementa `10-lacunas-e-melhorias.md` (que trata do panorama geral).

> **Desatualizado em relação à autorização (A2, ponto 2 do resumo).** Depois desta revisão, o `settings.py` passou a ter `DEFAULT_PERMISSION_CLASSES = [IsAuthenticated]` e `AccessAccount` ganhou o perfil `role` (`DRIVER`/`EMPLOYEE`/`MANAGER`, migração `core/migrations/0006_access_account_role.py`), com `IsManager`/`IsDriver`/`IsManagerOrDriver` em `core/permissions.py` (ver `database/03-migrations-e-superuser.md`, §2). O achado de que "a API é pública por padrão" **não vale mais como estava escrito**; A1, A3–A13 (que não dependem de `DEFAULT_PERMISSION_CLASSES`) continuam válidos até nova conferência. Esta seção não foi reauditada viewset a viewset — trate A2 como precisando de nova leitura, não como corrigido nem como ainda quebrado.

Severidade: **Crítica** (explorável / quebra o modelo de segurança), **Alta**, **Média**, **Baixa**.

---

## 1. Resumo executivo

1. **O refresh token (7 dias) funciona como token de acesso.** `AUTH_TOKEN_CLASSES` inclui a classe de refresh, então ele autentica chamadas normais e anula o access de 60 minutos.
2. **Só 4 rotas exigem login** (as 3 do motorista e `auth/change-password/`). Todo o resto da API, inclusive `POST route-events/` e `PATCH route-passengers/` (as ações que um app de motorista naturalmente precisa), é público e sem checagem de dono. Ligar a autenticação global quebra qualquer cliente que dependa deles até existirem endpoints seguros equivalentes.
3. **Trocar ou resetar a senha não derruba sessões antigas**, e `must_change_password` nunca é imposto no servidor.
4. **Identificador de login frágil:** e-mail derivado de `matrícula@domínio`, sem unicidade de matrícula e com domínio derivado só da 1ª palavra da empresa. Colisões deixam pessoas **sem conta e sem aviso**.
5. **Redefinição por OTP:** sem limite de tentativas, sem intervalo entre pedidos e, com `DEBUG=True` (valor do `.env.example`), o código volta na própria resposta.
6. **Vocabulário do contrato inconsistente** (`access_token` × `refresh` × `token`), sinal claro de adaptação ao Flutter que convém padronizar antes do Kotlin.
7. **Redundâncias:** três endpoints para pessoas, `full_clean`/`save` duplicados nos serializers, blocos de `Prefetch` copiados três vezes e ignorados pelo serializer (N+1), lógica de senha inicial em três lugares, código morto.

---

## 2. Autenticação — conflitos e brechas

### A1 · Crítica — Refresh token aceito como Bearer
`config/settings.py:168-171`

```python
"AUTH_TOKEN_CLASSES": (
    "core.tokens.AccessAccountAccessToken",
    "core.tokens.AccessAccountRefreshToken",   # ← não deveria estar aqui
),
```

`JWTAuthentication.get_validated_token` percorre `AUTH_TOKEN_CLASSES` e aceita o primeiro tipo que valida. Com a classe de refresh listada, `Authorization: Bearer <refresh_token>` autentica em `AccessAccountJWTAuthentication.get_user`. O padrão do SimpleJWT lista apenas o access. Provável origem: o `TokenVerifyView` precisava validar os dois tipos (ver docstring de `AccessAccountTokenVerifyView`, "access ou refresh").

**Efeito:** um refresh vazado vale 7 dias de acesso à API, e o app pode "nunca renovar" sem perceber.
**Correção:** manter só `AccessAccountAccessToken` em `AUTH_TOKEN_CLASSES`. O `TokenVerifyView` usa `UntypedToken` e continua verificando os dois tipos sem depender dessa lista.

### A2 · Crítica — Autorização inexistente fora do app do motorista
Não há `DEFAULT_PERMISSION_CLASSES` (⇒ `AllowAny`). Só `my-routes`, `driver-detail` (`IsAuthenticated + IsDriver`), `navigation` e `auth/change-password/` exigem token. As ações que um app de motorista precisa hoje só existem em endpoints abertos (confirme no código do app Flutter quais ele realmente chama):

| Ação do app | Endpoint usado | Proteção atual |
|-------------|----------------|----------------|
| Registrar saída/atraso/incidente | `POST route-events/` | nenhuma; aceita qualquer `route` |
| Confirmar embarque / ausência | `PATCH route-passengers/{id}/` | nenhuma; qualquer campo, qualquer passageiro |
| Ver eventos da rota | `GET routes/{id}/events/` | nenhuma; qualquer rota |

Também não há escopo por empresa: um usuário autenticado (inclusive um funcionário) poderia ler e alterar dados de qualquer empresa, se a proteção global for ligada sem mais nada.

**Correção sugerida (antes do Kotlin):**
- `DEFAULT_PERMISSION_CLASSES = [IsAuthenticated]`.
- Endpoints dedicados ao motorista, com checagem de dono (`route.vehicle.driver == request.user.person`): `POST routes/{id}/events/` e `PATCH routes/{id}/passengers/{rp_id}/boarding-status/` (aceitando **só** `boarding_status`).
- Permissões de gestão (`IsManager`) para o CRUD administrativo e `get_queryset` filtrado por `person.company_id` nos demais perfis.
- Se o app de funcionário for criado, prever `GET routes/my-boarding/` para `EMPLOYEE`; hoje só `DRIVER` tem visão própria.

### A3 · Alta — `must_change_password` é decorativo e o claim fica obsoleto
- Nenhuma permission/middleware bloqueia quem tem `must_change_password=True`: com o token do primeiro login, tudo funciona sem trocar a senha.
- O valor é gravado como **claim** do token (`tokens.py`, `for_access_account`). O endpoint de refresh (`auth_serializers.py:93-128`) emite o novo access a partir do claim do **refresh antigo**. Depois de `change-password` ou de um reset (que zera a flag no banco), quem renova com o refresh emitido antes continua recebendo `must_change_password=true`. O app decidiria a tela pelo claim errado.
- **Correção:** impor no servidor (`class PasswordChangeRequired(BasePermission)` aplicada globalmente, com exceção de `auth/change-password/`) e não confiar no claim; ou reemitir o claim a partir do banco no refresh.

### A4 · Alta — Sessões antigas sobrevivem à troca/reset de senha
`CHECK_REVOKE_TOKEN=False`, sem app de blacklist, e o refresh não rotaciona. Após `ChangePasswordView` ou `PasswordResetCompleteView`, qualquer refresh emitido antes segue válido por até 7 dias. É o cenário do celular perdido ou da conta comprometida: mudar a senha não expulsa o invasor.
**Correção:** guardar um `token_version` (ou `password_changed_at`) na `AccessAccount`, incluí-lo como claim e compará-lo em `AccessAccountJWTAuthentication.get_user` e no refresh. Alternativa: `rest_framework_simplejwt.token_blacklist` + `ROTATE_REFRESH_TOKENS`.

### A5 · Alta — Colisão de identificador: pessoa sem login e sem aviso
Login = `{employee_code|license_number}@{domínio}`. Problemas combinados:

- `Person.employee_code` e `license_number` **não são únicos** (nem por empresa) — `models.py:96-97`.
- O domínio vem de `Company.email_domain` ou da **primeira palavra** do nome (`derive_email_domain_from_company_name`). "Samsung Manaus" e "Samsung Brasil" geram `samsung.com`; matrículas iguais colidem.
- `signals.py:_create_access_account_if_missing` e `sync_access_account_email_for_person` só fazem `logger.warning` ao colidir: a `Person` é criada com sucesso (HTTP 201) e **não tem conta**. O cadastro parece certo e o login falha.
- Mudar `employee_code` ou `email_domain` **troca o e-mail de login** (sincronização automática). Um app Kotlin que guarde o e-mail no dispositivo passa a falhar sem explicação.
- Normalização do e-mail remove espaços e põe em minúsculas, então `AB 1` e `ab1` colidem.

**Correção:** `UniqueConstraint(company, employee_code)` e `(company, license_number)` com condição `is_active`; devolver erro 400 no cadastro quando o e-mail automático já existir; decidir se o login deve continuar mudando junto com o código (recomendo desacoplar: login estável, e-mail exibido como dado separado).

### A6 · Alta — Redefinição de senha por OTP
`auth_views.py:102-190`, `password_reset.py`.
- **Sem limite de tentativas:** `verify` e `reset` aceitam tentativas ilimitadas dentro da janela de 15 min (só o throttle anônimo de 100/h por IP). O espaço de um OTP de 6 dígitos é 1.000.000.
- **Sem intervalo entre pedidos:** cada `request` sobrescreve o código anterior; um terceiro que conheça o e-mail pode invalidar continuamente o código do usuário legítimo. `password_reset_requested_at` existe mas não é usado para limitar.
- **Telefone ambíguo:** a busca por `phone` devolve a **primeira** conta ativa cuja versão só-dígitos coincide, em qualquer empresa; percorre todas as contas em Python. Duas pessoas com o mesmo telefone ⇒ o reset pode cair na conta errada.
- **OTP na resposta:** `PASSWORD_RESET_RETURN_CODE_IN_RESPONSE` usa `DEBUG` como padrão e o `.env.example` traz `DEBUG=True`. Quem copiar o exemplo para produção expõe o código para qualquer e-mail/telefone conhecido: tomada de conta sem nenhum segredo.
- **Sem canal de entrega:** o fluxo só é utilizável no modo debug (já apontado em `S-04`).
- **Correção:** contador de tentativas no OTP (invalidar após ~5), cooldown de 60 s entre pedidos, telefone normalizado e indexado com unicidade, e a flag de retorno do código desacoplada de `DEBUG` (padrão `False`).

### A7 · Média — Enumeração de contas e bloqueio como ataque de negação
`auth_serializers.py:26-90`.
- A mensagem "Conta temporariamente bloqueada." só aparece para e-mails **existentes**, e a checagem de bloqueio vem antes das de conta inativa/senha. Isso revela quais e-mails são válidos.
- Como o e-mail é previsível (`matrícula@empresa.com`) e o bloqueio é por conta (5 falhas ⇒ 30 min), qualquer pessoa consegue travar o login de terceiros sem credencial alguma.
- **Correção:** resposta uniforme "Credenciais inválidas" (ou 429 genérico), bloqueio também por IP/dispositivo, e avaliar atraso progressivo em vez de bloqueio duro.

### A8 · Média — Senha inicial previsível
`access_passwords.py`: `matrícula + 4 últimos dígitos do telefone`. Combinado a e-mail previsível e sem verificação de posse, quem conhece um colega acerta a senha inicial de quem ainda não logou. `ACCESS_ACCOUNT_AUTO_INITIAL_PASSWORD`, se definida, faz **todas** as contas nascerem com a mesma senha.
**Correção:** senha temporária aleatória entregue por canal seguro, ou link/OTP de ativação; manter `must_change_password` imposto (A3).

### A9 · Média — Contrato de tokens com três vocabulários
| Endpoint | Entrada | Saída |
|----------|---------|-------|
| `auth/login/` | `email`, `password` | `access_token`, `refresh_token`, `must_change_password`, `person` |
| `auth/refresh/` | `refresh` | `access_token` (não devolve novo refresh) |
| `auth/verify/` | `token` | corpo vazio |
| `auth/change-password/` | `current_password`, `new_password` | igual ao login |

O padrão do SimpleJWT usaria `access`/`refresh`. As saídas foram renomeadas para o Flutter, mas o refresh continua exigindo `refresh`. Antes do Kotlin, escolher **um** padrão (ex.: `access_token`/`refresh_token` em toda a API) e documentar em OpenAPI (ver B-09).

### A10 · Média — `navigation`: autorização manual, vazamento e `print`
`viewsets.py:163-190`. O resto do app usa `IsDriver`; aqui há um `if person.type != DRIVER` manual que devolve `person_id` e `person_type` no corpo do 403 e faz `print()` com `account_id`, `person_id` e tipo a cada chamada (sobra de depuração com o Flutter). Trocar por `permission_classes=[IsAuthenticated, IsDriver]`, remover o `print` e a devolução desses campos.

### A11 · Média — `SECRET_KEY` padrão assina os JWT
`settings.py:12`: o valor padrão é `insecure-key-change-me`. Se a variável faltar em produção, qualquer pessoa que conheça o padrão consegue **forjar tokens válidos** para qualquer `access_account_id`. Fazer a aplicação falhar ao iniciar sem `SECRET_KEY` quando `DEBUG=False`.

### A12 · Baixa — Duas identidades convivendo
O admin do Django usa `auth.User` (sem nenhum model registrado em `admin.py`), enquanto a API usa `AccessAccount`. Não há conflito técnico, mas quem entra no admin não tem ligação com quem entra no app. Deixar isso explícito na documentação, ou remover `django.contrib.admin` se não for usado.

### A13 · Baixa — Throttle anônimo compartilhado
`AnonRateThrottle` (100/h) por IP afeta login e reset de senha. Motoristas atrás do mesmo NAT móvel/empresarial dividem a cota. Definir `throttle_scope` próprio para `auth/*` (ex.: 20/min por IP + por e-mail).

---

## 3. Redundâncias e código morto

| ID | Local | Problema | Ação |
|----|-------|----------|------|
| R1 | `viewsets.py:79-82, 299-308`, `filters.py` | Três caminhos para a mesma tabela: `people/`, `drivers/`, `employees/`. `DriverViewSet`/`EmployeeViewSet` já filtram `type` no queryset **e** `DriverFilter`/`EmployeeFilter` refiltram na propriedade `qs` | Manter `people/?type=` e um só par especializado; remover a sobrescrita de `qs` |
| R2 | `serializers.py:34-62` + `models.py:112-114` | `Person.save()` já chama `full_clean()`; `PersonSerializer.create/update` chamam `full_clean()` + `save()` de novo ⇒ 3 validações e **2 saves por requisição**, disparando o `post_save` (criação de conta e sincronia de e-mail) duas vezes | Remover o pós-processamento e apenas converter `DjangoValidationError` num helper único |
| R3 | `serializers.py:110-165` | `DriverSerializer`/`EmployeeSerializer` **não** convertem `DjangoValidationError`; `validate_license_number`/`validate_employee_code` não rodam quando o campo é omitido (campos opcionais). `POST drivers/` sem `license_number` chega ao `Person.save()` e provavelmente vira **erro 500** em vez de 400. Também são mortos: `data.get("employee_code")` (campo fora de `fields`) | Validar no `validate()` (exigir o campo do tipo) e reaproveitar o mesmo tratamento do `PersonSerializer` |
| R4 | `viewsets.py:96-156, 195-201` | O bloco de `Prefetch` (stops, passageiros, eventos) aparece **3 vezes** (~60 linhas) | Extrair `driver_routes_queryset(person)` |
| R5 | `driver_serializers.py:20-60` | O serializer ignora os prefetches: `route.stops.select_related().filter().order_by()`, `stop.passengers.filter().count()` por parada, `route.route_passengers...filter()` e `route.events.order_by().first()` geram novas consultas. Os `Prefetch` do viewset são desperdiçados e há N+1 (1 + paradas + 3 consultas por rota) | Filtrar no `Prefetch(..., to_attr=...)` e ler os atributos no serializer; calcular `passenger_count` em Python |
| R6 | `viewsets.py:157-162` × `RouteEventViewSet` | `routes/{id}/events/` duplica `route-events/?route_id=` e não tem permissão | Manter um; se for o do motorista, proteger por dono (A2) |
| R7 | `viewsets.py:163-190` | Checagem manual de motorista duplica `IsDriver` (A10) | Usar a permission |
| R8 | `serializers.py:18-25` | `BaseSerializer` redeclara `id`, `created_at`, `updated_at` (já são somente leitura no `ModelSerializer`) e `is_active` com `default=True`; `class Meta: abstract = True` não tem efeito no DRF. Efeito colateral: `PUT` sem `is_active` **reativa** o registro | Remover a redeclaração e o `abstract` |
| R9 | `models.py` (`ActiveManager`, `objects`/`active`) | `Model.active` **não é usado em nenhum lugar**. `BaseViewSet.get_queryset` tem `hasattr(self.queryset.model, "is_active")` sempre verdadeiro | Remover o manager ou usá-lo nos viewsets |
| R10 | `signals.py`, `ensure_access_accounts.py`, `reset_initial_access_passwords.py` | A regra da senha inicial existe em três fluxos; a ajuda de `ensure_access_accounts --password` ainda descreve a regra antiga ("DDMMAAAA de created_at") | Uma função `provision_access_account(person)` usada pelos três; corrigir o texto |
| R11 | `auth_views.py:25-95` | O objeto de resposta `{access_token, refresh_token, must_change_password, person}` é montado duas vezes (login e change-password) | Helper `build_session_payload(account)` |
| R12 | `settings.py:150-158` | `SearchFilter` e `OrderingFilter` globais são anulados por `BaseViewSet.filter_backends` (e não há `search_fields`) | Remover ou habilitar de fato |
| R13 | `models.py`/`core/admin.py` | `admin.py` vazio (nenhum model registrado); `core/views.py` e `core/tests.py` são apenas os stubs | Remover os stubs ou usar o admin |

### Arquivos soltos e restos de desenvolvimento

- **`core_data.json`** (raiz do backend): dump com 3 empresas, 4 pessoas e 4 contas de acesso, incluindo **nomes, telefones, matrículas/CNH, e-mails, hashes de senha e o hash de um OTP já expirado**. Não está no `.gitignore`. Se já foi versionado, considere o conteúdo comprometido: redefinir essas senhas e limpar o histórico. Substituir por dados fictícios (o comando `seed_manaus_demo` já cobre isso).
- **`data.json`** (UTF-16, lista vazia), **`main.py`** (0 bytes), **`db.sqlite3`** (0 bytes): remover.
- **Comentário em `settings.py:15`** ("Flutter emulador/device") e `ALLOWED_HOSTS=["*"]` em `DEBUG`: revisar o texto para o Kotlin; o curinga só deve existir em desenvolvimento.
- **`README.md` / `PT-README.md`**: descrevem UUID, soft delete e permissões "a configurar"; divergem do código (ver `10-lacunas-e-melhorias.md`, D-01/D-02).

---

## 4. Checklist para o app Kotlin

Decisões a fechar **antes** de o cliente Kotlin depender do contrato:

1. **Contrato de sessão único** (A9): nomes dos campos, `refresh` que devolve novo refresh (rotação) e códigos de erro (`401` credenciais/token, `403` perfil, `423`/`429` bloqueio/limite).
2. **Endpoints do motorista protegidos por dono** (A2): eventos e status de embarque. Enquanto não existirem, o app Kotlin herdaria os endpoints abertos.
3. **Fluxo de primeiro acesso** imposto no servidor (A3) e senha inicial não previsível (A8).
4. **Login estável**: resolver A5 para que o e-mail guardado no aparelho não mude sozinho.
5. **Sessão**: access curto, refresh em armazenamento seguro do Android (Keystore/EncryptedSharedPreferences), invalidação por versão de senha (A4) e tratamento de 401 com uma renovação e nova tentativa.
6. **Recuperação de senha** com canal real de entrega e limites (A6).
7. **Perfil funcionário**: definir se o app terá visão própria (rotas em que é passageiro) e criar o endpoint correspondente.
8. **Esquema OpenAPI** (drf-spectacular já instalado) para gerar o cliente Kotlin em vez de mapear à mão: expor `/api/schema/` e anotar as views de `auth/*`.

## 5. Como confirmar A1 e A4 (teste de 10 linhas)

Em `core/tests.py`, com as dependências instaladas:

```python
from rest_framework.test import APITestCase
from core.models import Company, Person, AccessAccount

class AuthConflictTests(APITestCase):
    def setUp(self):
        c = Company.objects.create(name="Acme")
        p = Person.objects.create(company=c, name="Motorista", phone="92999990000",
                                  type="DRIVER", license_number="123456")
        self.acc = AccessAccount.objects.get(person=p)      # criada pelo signal
        self.pw = "1234560000"                              # licença + 4 últimos do telefone

    def _login(self):
        r = self.client.post("/api/auth/login/", {"email": self.acc.email, "password": self.pw})
        assert r.status_code == 200, r.content
        return r.json()

    def test_a1_refresh_nao_deve_autenticar(self):
        t = self._login()
        r = self.client.get("/api/routes/my-routes/",
                            HTTP_AUTHORIZATION=f"Bearer {t['refresh_token']}")
        self.assertEqual(r.status_code, 401)   # hoje deve falhar (retorna 200)

    def test_a4_refresh_antigo_apos_trocar_senha(self):
        t = self._login()
        self.client.post("/api/auth/change-password/",
                         {"current_password": self.pw, "new_password": "NovaSenha!2026x"},
                         HTTP_AUTHORIZATION=f"Bearer {t['access_token']}")
        r = self.client.post("/api/auth/refresh/", {"refresh": t["refresh_token"]})
        self.assertEqual(r.status_code, 401)   # hoje deve falhar (retorna 200)
```

Os dois testes são a especificação do comportamento desejado: se falharem hoje, o problema está confirmado; depois da correção, passam a proteger contra regressão.

## 6. Ordem sugerida

1. **Já:** A1 (uma linha), A11, A6 (OTP e flag de debug), A10, remover/limpar `core_data.json` e trocar/rotacionar a chave do `.env.example` (`S-02`).
2. **Antes do Kotlin:** A2 (permissões e endpoints do motorista), A3, A4, A5, A9, checklist da seção 4.
3. **Em seguida:** A7, A8, A12, A13 e as redundâncias R1–R13, começando por R2/R3 (bug provável de 500) e R4/R5 (desempenho de `my-routes`).
