# 10 — Lacunas, divergências e melhorias sugeridas

Levantamento feito a partir da leitura do código. Não altera o comportamento descrito nas demais specs; serve como backlog priorizado. Prioridade: **A** alta, **M** média, **B** baixa.

## 1. Segurança

| ID | Prio | Achado | Sugestão |
|----|------|--------|----------|
| S-01 | A | ~~Nenhum viewset CRUD exige autenticação~~ — **parece resolvido**: `DEFAULT_PERMISSION_CLASSES` no `settings.py` atual já é `IsAuthenticated`, e `core/permissions.py` ganhou `IsManager`/`IsDriver`/`IsManagerOrDriver` (via `AccessAccount.role`, migração `0006_access_account_role`) | Confirmar que cada viewset usa a permissão certa por perfil (gestor × motorista × funcionário) e que o frontend já envia o token (ver F-01/I-07) — não reauditado viewset a viewset nesta sessão |
| S-02 | A | `.env.example` contém o que parece ser uma **chave real** de API do Google (`GOOGLE_MAPS_API_KEY`) | Revogar/rotacionar a chave, restringi-la por API/origem no Google Cloud e substituir por placeholder no exemplo. Verificar o histórico do Git |
| S-03 | A | `SECRET_KEY` tem valor padrão inseguro e `CORS_ALLOW_ALL_ORIGINS = True` | Falhar na inicialização sem `SECRET_KEY` em produção; restringir `CORS_ALLOWED_ORIGINS` |
| S-04 | M | `PASSWORD_RESET_RETURN_CODE_IN_RESPONSE` segue `DEBUG`; o reset por OTP não tem envio por e-mail/SMS, então em produção o fluxo não é utilizável | Integrar canal de entrega (e-mail/SMS) e manter o retorno do código apenas em desenvolvimento |
| S-05 | M | Senha inicial previsível (matrícula + últimos 4 dígitos do telefone) | Manter `must_change_password=True` (já ocorre) e considerar senha temporária aleatória ou link de ativação |
| S-06 | M | `resolve_access_account_for_reset` por telefone percorre todas as contas em Python | Guardar telefone normalizado indexado para consulta direta |
| S-07 | B | Login não rotaciona nem invalida refresh tokens (`CHECK_REVOKE_TOKEN=False`, sem blacklist) | Avaliar rotação/blacklist do SimpleJWT |
| S-08 | B | `print()` de depuração em `RouteViewSet.navigation` (`[route-navigation] …`) | Trocar por `logging` |
| S-09 | A | ~~`build_database_config` caía silenciosamente para SQLite quando `DATABASE_URL` estava ausente/vazia~~ — **resolvido**: `DATABASE_URL` agora é obrigatória e restrita a `postgres(ql)://` (falha a subida caso contrário); `sslmode`/`conn_max_age` já são aceitos | Ver `database/04-postgres-exclusivo.md` (aplicado ao `config/settings.py` e ao `.env.example` nesta sessão) |

## 2. Backend — bugs e robustez

| ID | Prio | Achado | Sugestão |
|----|------|--------|----------|
| B-01 | A | `VehicleSerializer.driver` é somente leitura; o frontend envia `driver` (ver I-01) | Aceitar `driver` como PK na escrita, ou ajustar o cliente para `driver_id` |
| B-02 | M | `RoutePassengerSerializer.validate_person_id` usa `Person.objects.get` sem tratar `DoesNotExist` ⇒ erro 500 para id inexistente | Capturar a exceção e devolver `ValidationError` (como já é feito em `validate_driver_id`) |
| B-03 | M | Paginação sem `page_size_query_param` (I-02) | Criar classe de paginação com `page_size_query_param="page_size"` e `max_page_size` |
| B-04 | M | `DELETE` físico com CASCADE amplo (excluir `Company` apaga tudo abaixo) apesar do campo `is_active` | Adotar soft delete (`is_active=False`) no `destroy` ou `on_delete=PROTECT` nas relações críticas |
| B-05 | M | `BaseViewSet` filtra `is_active=True` também no detalhe: um registro desativado retorna 404 e não pode ser reativado via API | Filtrar apenas em `list` ou aceitar `?is_active=` |
| B-06 | M | `RoutePassengerSerializer.validate_route_stop_id` depende de `initial_data["route"]`; em `PATCH` sem `route` só valida quando há `instance` | Validar no `validate()` com o objeto completo |
| B-07 | M | Origem/destino da navegação são inferidos ("primeiro endereço") sem regra explícita de qual endereço é a sede/destino da empresa | Modelar destino explicitamente (por exemplo, `Route.destination` ou flag em `Address`) |
| B-08 | B | `SearchFilter`/`OrderingFilter` configurados globalmente mas anulados por `BaseViewSet.filter_backends`; sem `search_fields` | Remover do settings ou habilitar de fato |
| B-09 | B | drf-spectacular instalado e configurado, sem URLs de schema/Swagger em `config/urls.py` | Expor `/api/schema/` e `/api/docs/` |
| B-10 | B | `LANGUAGE_CODE='en-us'`, `TIME_ZONE='UTC'` para um produto usado em Manaus | Avaliar `pt-br` e `America/Manaus` (cuidado com `TimeField` de `Schedule`) |
| B-11 | B | `core/views.py` e `core/tests.py` vazios; sem testes automatizados no backend | Cobrir auth, regras de `Person`/`RoutePassenger`/`RouteEvent` e `my-routes` |
| B-12 | B | `requirements.txt` em UTF-16 e inclui pacotes não usados (`git-filter-repo`, `Werkzeug`, `sqlparse` etc. misturados) | Regenerar em UTF-8 apenas com dependências do projeto |

## 3. Frontend

| ID | Prio | Achado | Sugestão |
|----|------|--------|----------|
| F-01 | A | Sem login, guard nem interceptor de token (I-07) | Tela de login (`auth/login/`), armazenamento de tokens, `AuthInterceptor` com refresh, `CanActivate` nas rotas, fluxo `must_change_password` |
| F-02 | A | Selects/mapas carregam só a primeira página (I-03, I-04) | Buscar todas as páginas ou usar autocomplete com busca no servidor; para motoristas usar `people/?type=DRIVER` ou `drivers/` |
| F-03 | M | Erros da API não são mostrados ao usuário (I-14) | Snackbar (Material) com mensagens dos campos retornados pelo DRF |
| F-04 | M | Exclusão usa `confirm()` nativo; existe `DialogComponent` não utilizado | Usar `MatDialog` com o `DialogComponent` |
| F-05 | M | Usuário do topo fixo ("Maria Gestora"); Dashboard/Mapa/Relatórios/Configurações em manutenção; `DashboardComponent` sem rota e com data fixa | Ligar ao usuário logado; implementar telas ou ocultar do menu |
| F-06 | M | Sem telas para pontos de encontro, paradas de rota e passageiros de rota, essenciais ao fluxo do motorista | Criar CRUDs (ou um editor de rota com paradas ordenáveis e passageiros) |
| F-07 | M | `weekdays` como texto livre (I-10); `event_type` sem opções fixas (I-06); `email_domain` ausente (I-09) | Multi-select de dias, select de tipos e campo de domínio |
| F-08 | B | Listas repetem lógica de paginação/carregamento; `getXFromResponse` duplicado em vários componentes | Extrair helpers/`BaseListComponent`; usar `extractPaginatedItems` em todos |
| F-09 | B | `environment.ts` e `app.urls.ts` sem uso; `config.json` com IP fixo (I-11) | Padronizar em `config.json` e remover o código morto |
| F-10 | B | Módulo/rotas legados em `features/employee` (`employee.module.ts`, `employee-routing.module.ts`) coexistem com standalone routes | Remover se não usados |
| F-11 | B | Rota `**` ausente; `console.debug` em toda requisição; testes só para 3 componentes | Página 404, remover logs em produção, ampliar testes |

## 4. Documentação divergente do código

| ID | Prio | Divergência | Correção |
|----|------|-------------|----------|
| D-01 | M | `PT-README.md` (backend) cita **UUID** como chave primária e **soft delete** ao "desativar" empresas | O código usa `BigAutoField` e `DELETE` físico (ver `02-modelo-de-dados.md`, RN-28) |
| D-02 | M | `PT-README.md` fala de "um motorista ativo" por rota | Não há esse campo: o motorista vem de `route.vehicle.driver` |
| D-03 | B | `docs/INSTRUCOES_API_PEOPLE_ANGULAR.md` descreve autenticação como recomendada; na prática nada exige token | Atualizar após S-01 |
| D-04 | B | `README.md` do frontend descreve `features/` conceitual (`companies/`, `people/`, `routes/`) | Nomes reais: `company`, `employee`, `vehicle`, `route`, `schedule`, `route-event`, `report` |
| D-05 | B | Ajuda de `ensure_access_accounts --password` cita "DDMMAAAA de created_at", mas o código usa matrícula + telefone | Atualizar o texto de ajuda |

## 5. Sugestão de ordem de execução

1. S-02 (rotacionar chave). S-09 (PostgreSQL exclusivo) já está aplicado; S-01 (autenticação da API) parece já resolvido no backend — falta confirmar/ligar o F-01 (login e interceptor no frontend).
2. B-01/I-01 (motorista do veículo), B-03/I-02 (`page_size`), F-02/I-03 (selects paginados).
3. F-03, F-04, B-02, B-04.
4. Telas ausentes (F-06) e dashboard/mapa (F-05).
5. Testes, documentação e limpeza (B-11, B-12, D-*, F-08 a F-11).
