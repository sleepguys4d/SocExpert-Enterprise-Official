<div align="center">

# SOC Xpert
### Plataforma de Operações de Segurança Unificada · by Sec4data

*Uma única consola para SIEM, NDR, EDR, Firewall, Threat Intel e SOAR — com Copilot de IA em todo o ciclo de deteção e resposta.*

</div>

---

## O que é

O **SOC Xpert** unifica a telemetria e a resposta de um SOC moderno numa só interface: ingestão de eventos (Wazuh), análise de rede (Malcolm/Zeek), endpoint (Velociraptor), perímetro (OPNsense), inteligência de ameaças (MISP) e gestão de casos/SOAR (TheHive/Cortex). Inclui um **Copilot** que apoia o analista na triagem, investigação, *threat hunting* e resposta.

Foi desenhado com **degradação graciosa**: arranca imediatamente em **modo DEMO** (dados simulados realistas) e passa a **modo LIVE** assim que configuras os conectores reais — sem alterar código.

### Módulos
- **Centro de Comando** — KPIs, volume de eventos, severidade, heatmap MITRE ATT&CK, saúde dos sensores, origem geográfica das ameaças.
- **Eventos & Alertas** — stream unificado e filtrável de todas as fontes.
- **Incidentes** — gestão de casos em *kanban* (Novo → Em Análise → Contido → Resolvido).
- **Investigação** — entidades, *threat intel* e linha temporal do ataque reconstruída.
- **Threat Hunting** — consola de caça (Sigma / Wazuh QL) com execução e *hunts* guardados.
- **Resposta & Playbooks** — orquestração SOAR (isolar, bloquear, desativar, quarentena…).
- **Integrações** — estado e métricas de cada conector.
- **SOC Copilot** — assistente de IA (Anthropic Claude) com *fallback* local.

---

## Arranque rápido (Docker)

Pré-requisitos: **Docker** + **Docker Compose**.

```bash
# 1. (opcional) criar o ficheiro de configuração
cp .env.example .env

# 2. construir e arrancar
docker compose up --build
```

Abre **http://localhost:4000** — a plataforma arranca em **modo DEMO**, totalmente navegável.

> Um único contentor serve a API **e** o frontend compilado na mesma porta (4000).

---

## Passar a produção (modo LIVE)

Edita o `.env`, coloca `DEMO_MODE=false` e preenche os conectores que tens:

```env
DEMO_MODE=false

# Wazuh
WAZUH_API_URL=https://wazuh.tua-rede:55000
WAZUH_API_USER=wazuh-wui
WAZUH_API_PASSWORD=********
WAZUH_INDEXER_URL=https://wazuh.tua-rede:9200
WAZUH_INDEXER_USER=admin
WAZUH_INDEXER_PASSWORD=********

# MISP
MISP_URL=https://misp.tua-rede
MISP_API_KEY=********

# TheHive
THEHIVE_URL=http://thehive.tua-rede:9000
THEHIVE_API_KEY=********

# Copilot
ANTHROPIC_API_KEY=sk-ant-********
```

Volta a subir: `docker compose up --build -d`. Cada conector é avaliado de forma **independente** — os que estiverem configurados passam a LIVE; os restantes mantêm dados de demonstração, para nunca teres uma consola vazia.

### Mapeamento dos conectores

| Conector | Usa | Para quê |
|----------|-----|----------|
| **Wazuh** | API do manager (`:55000`) + Indexer/OpenSearch (`:9200`) | Saúde, agentes e pesquisa de alertas `wazuh-alerts-*` |
| **MISP** | REST `/attributes/restSearch` | Enriquecimento de IOCs |
| **TheHive 5** | `/api/v1` | Listar e criar casos (incidentes) |
| **Anthropic** | `/v1/messages` | Respostas do Copilot |

---

## Fase 03 · Base de dados e identidade

A partir da Fase 03, o SOC Xpert tem uma **fundação de persistência e identidade** —
base para autenticação, perfis, papéis (RBAC) e multitenancy. A sub-fase **03.1**
entregue aqui é a **fundação** e é totalmente **aditiva**: sem `DATABASE_URL`, a app
continua a arrancar como antes (modo legado, `.env` / demo).

O que a fundação inclui:

- **PostgreSQL + Prisma** — esquema com organizações (tenants), utilizadores,
  papéis, conectores por tenant, preferências, sessões e auditoria.
- **Cifragem de credenciais** — as credenciais dos conectores são guardadas
  **cifradas** (AES-256-GCM), nunca em texto simples.
- **Seed idempotente** — no primeiro arranque cria o tenant por defeito, o
  administrador (se definires a palavra-passe) e migra os conectores do `.env`
  para a base de dados, já cifrados.

O `docker-compose` já inclui o serviço **PostgreSQL**; só precisas de definir
duas variáveis no `.env`:

```bash
cp .env.example .env

# 1. chave de cifragem (32 bytes)
openssl rand -base64 32      # → cola em APP_ENCRYPTION_KEY

# 2. palavra-passe do administrador inicial
#    define ADMIN_PASSWORD no .env

docker compose up --build
```

No arranque verás o estado da fundação nos logs:

```
· Base de dados: ligada
· Origem dos conectores: base de dados (por tenant)
```

> A **autenticação** (sub-fase 03.2) está implementada: ecrã de login, sessões
> em *cookie* `httpOnly`, rotas protegidas e RBAC. O login torna-se obrigatório
> assim que existe um administrador (ver *Implantação em produção*).

## Firewalls · ingestão de syslog

Além dos conectores que fazem *polling* às APIs (Wazuh, MISP, TheHive), o SOC
Xpert recebe **logs de firewall por syslog** (modelo *push*). As firewalls
enviam para o IP deste host e os eventos aparecem no *stream* de **Eventos**, a
par dos restantes, com a saúde do recetor visível em **Integrações**.

Formatos reconhecidos: **OPNsense / pfSense** (`filterlog` CSV), **FortiGate**
(`key=value`), **Cisco ASA** (`%ASA-…`) e **Palo Alto / genérico** (CSV / regex),
com enquadramento **RFC 3164** e **RFC 5424**, em UDP e TCP.

Com `docker compose`, o host escuta na porta **514** (padrão de syslog) e
encaminha para o contentor. Aponta a firewall para `IP_DO_HOST:514`:

| Firewall | Onde configurar |
|----------|-----------------|
| **OPNsense** | *System → Settings → Logging / Remote* → servidor remoto `IP:514`, protocolo UDP |
| **pfSense** | *Status → System Logs → Settings* → *Remote Logging* → `IP:514` |
| **FortiGate** | `config log syslogd setting` → `set server IP`, `set port 514` |
| **Cisco ASA** | `logging host inside IP`, `logging trap informational` |

Variáveis em `.env`: `SYSLOG_ENABLED`, `SYSLOG_HOST_PORT` (porta no host),
`SYSLOG_UDP` / `SYSLOG_TCP`, `SYSLOG_MAX_EVENTS`. Em modo DEMO são injetadas
linhas de exemplo para a funcionalidade ser visível sem firewall ligada.
Diagnóstico em tempo real: `GET /api/syslog/stats`.

> Multitenancy (03.5): o mapeamento `SYSLOG_TENANT_MAP=ip=tenant,…` já permite
> atribuir cada firewall a uma organização; a aplicação plena chega nessa fase.

## Integrações por interface gráfica

Todas as integrações configuram-se e ativam-se **na própria consola** (página
*Integrações*) — sem editar ficheiros nem reiniciar. Cada integração tem:

- um **interruptor** de ativar/desativar (aplicado em tempo real — o recetor de
  syslog, por exemplo, liga/desliga na hora);
- um **formulário** com os campos certos para o tipo (URL, chaves, TLS…), gerado
  a partir do catálogo de conectores;
- um botão **Testar** que faz uma sondagem real ao alvo e devolve o resultado;
- distintivos de estado: *Configurado / Por configurar* e origem (*BD / Memória / .env*).

As credenciais são **cifradas** (AES-256-GCM) e guardadas na base de dados quando
esta existe; sem base de dados, ficam em memória durante a sessão (semeadas a
partir do `.env`). Os segredos nunca são devolvidos à interface — ao editar, um
campo de segredo vazio mantém o valor atual.

O `.env` continua a funcionar como ponto de partida (semeia as integrações na
primeira vez); a partir daí, a GUI é a forma recomendada de gerir tudo. O
interruptor global `DEMO_MODE` mantém-se como mestre: em DEMO os dados são
simulados; em LIVE, cada integração ativada e configurada passa a ser consultada
a sério.

## Estender · integrar novas soluções

A plataforma foi desenhada para crescer. Há três formas de ligar uma solução
nova, do mais simples ao mais completo:

**1 · Webhook de entrada (sem código).** A via universal. Qualquer ferramenta
que saiba fazer um HTTP POST — SIEM, EDR, WAF, automação, API de um parceiro —
envia eventos JSON para `/api/ingest/webhook`, autenticando com um token. O
normalizador aceita formatos arbitrários (reconhece os nomes de campo mais
comuns), por isso não há formato fixo. Ativa-se em *Integrações* (tipo *Webhook
de Entrada*), definindo o token.

```bash
curl -X POST https://soc.teu-dominio.com/api/ingest/webhook \
  -H "X-SOCX-Token: <o-teu-token>" -H "Content-Type: application/json" \
  -d '{"source":"Splunk","severity":"critical","message":"Exfiltração detetada","src_ip":"10.20.7.9"}'
```

**2 · Conector genérico (só configuração).** Para alvos HTTP, a GUI já permite
adicionar e testar integrações por configuração (URL, chaves, TLS), sem código.

**3 · Plugin de dados (código).** Para recolha ativa (pull) de uma solução
específica, implementa-se o contrato do SDK de conectores — um `ProviderFactory`
que declara as capacidades (`health`, `events`, `incidents`, `enrich`) e
devolve os dados já normalizados. O agregador descobre-o automaticamente:

```
1. registry.ts   → declara a integração (desenha o formulário na GUI)
2. providers/…   → implementa o ProviderFactory (ver _example.ts)
3. register.ts   → registerProvider('chave', provider)
```

O ficheiro `server/src/services/connectors/providers/_example.ts` é um modelo
completo e comentado. Nada no núcleo precisa de mudar: a credencial fica
cifrada, a saúde e o teste de ligação ficam automáticos, e os dados entram no
stream unificado assim que a integração é ativada.

## Desenvolvimento (sem Docker)

```bash
# Backend (porta 4000)
cd server && npm install && npm run dev

# Frontend (porta 5173, com proxy /api → 4000)
cd web && npm install && npm run dev
```

Frontend de dev em **http://localhost:5173**.

---

## Arquitetura

```
soc-xpert/
├── docker-compose.yml      # orquestração (app + base de dados PostgreSQL)
├── Dockerfile              # multi-stage: build web → build server → runtime
├── .env.example            # todas as variáveis de ambiente
├── server/                 # API Node + TypeScript (Express)
│   ├── prisma/
│   │   ├── schema.prisma      # modelo de dados (Fase 03)
│   │   └── migrations/        # migrações SQL
│   ├── docker-entrypoint.sh   # migrate + seed no arranque (se houver BD)
│   └── src/
│       ├── config.ts           # configuração por ambiente
│       ├── crypto/secretbox.ts # cifragem AES-256-GCM de credenciais
│       ├── db/client.ts        # Prisma (com degradação graciosa)
│       ├── connectors/         # wazuh · misp · thehive · http (polling)
│       ├── ingest/syslog/       # recetor de syslog das firewalls (push)
│       ├── ingest/webhook/      # webhook de entrada — integração universal (push)
│       ├── services/           # aggregator · copilot · tenantConfig
│       │   └── connectors/      # SDK · registo · runtime (GUI) · providers · teste
│       ├── routes/api.ts       # endpoints REST
│       ├── mock/data.ts        # dataset de demonstração
│       ├── seed.ts             # seed: tenant + admin + conectores
│       └── index.ts            # servidor (API + estáticos)
└── web/                    # React 18 + TypeScript + Vite
    └── src/
        ├── components/         # Logo · TopBar · Sidebar · Copilot · ui
        ├── views/              # Dashboard · Events · Incidents · …
        ├── api.ts              # cliente tipado
        └── theme.css           # design system (HUD/SOC, cyan)
```

### API (resumo)
`GET /api/health` · `POST /api/auth/login` · `GET /api/auth/me` · `POST /api/ingest/webhook` · `GET /api/dashboard` · `GET /api/events?severity=` · `GET|POST /api/incidents` · `GET /api/integrations` · `GET /api/syslog/stats` · `GET /api/connectors` · `POST /api/connectors/:key` · `POST /api/connectors/:key/enable` · `POST /api/connectors/:key/test` · `DELETE /api/connectors/:key` · `GET /api/hunting/saved` · `POST /api/hunting/run` · `GET /api/response/actions` · `POST /api/response/run` · `GET /api/intel/:ioc` · `POST /api/copilot`

---

## Implantação em produção

A plataforma corre com `helmet` + **Content-Security-Policy**, `cors`, `compression`,
*rate-limiting* (240 req/min na API, 10/min no login), **autenticação com sessões**,
RBAC nas ações sensíveis, credenciais cifradas (AES-256-GCM), `trust proxy` para
TLS terminado à frente e contentor com utilizador **não-root**.

### Arrancar em produção

```bash
cp .env.example .env

# 1. Chave de cifragem das credenciais (obrigatória em produção):
openssl rand -base64 32        # → APP_ENCRYPTION_KEY

# 2. Administrador inicial (cria o login):
#    define ADMIN_EMAIL e ADMIN_PASSWORD no .env

# 3. Postura de produção no .env:
#    DEMO_MODE=false   COOKIE_SECURE=true   CORS_ORIGIN=https://o-teu-dominio

docker compose up --build -d
```

No arranque, o entrypoint aplica as migrações e o *seed* (cria o tenant e o
administrador). A consola passa a **exigir login**. Coloca-a atrás de um
*reverse proxy* com **HTTPS** (Nginx/Traefik/Caddy) apontando para a porta 4000.

### Acesso e autenticação

O **login torna-se obrigatório** assim que existe um administrador (criado pelo
`ADMIN_PASSWORD`/seed, ou qualquer utilizador na base de dados). Sem
administrador, a consola corre em **modo aberto** (demonstração) — útil para
testes, nunca para produção. As sessões usam *cookies* `httpOnly` (e `Secure`
em produção); o servidor guarda apenas o **hash** do token. Papéis: `OWNER`,
`ADMIN`, `ANALYST`, `VIEWER`, `AUDITOR` — a configuração de conectores e as
ações de resposta exigem `ADMIN`/`OWNER`.

### Checklist de segurança

- [ ] `APP_ENCRYPTION_KEY` gerada com `openssl rand -base64 32` (a app **recusa**
      arrancar em produção com a chave por defeito).
- [ ] `ADMIN_PASSWORD` definida (cria o administrador e ativa o login).
- [ ] `DEMO_MODE=false` para usar conectores reais.
- [ ] `COOKIE_SECURE=true` e a consola atrás de **TLS** (reverse proxy HTTPS).
- [ ] `CORS_ORIGIN` definido para o domínio real (não `*`).
- [ ] Wazuh/MISP/TheHive e o recetor de syslog em **rede privada**; desativa
      `*_INSECURE_TLS` quando tiveres certificados válidos.
- [ ] Segredos geridos via *secrets* do Docker/orquestrador.
- [ ] *Backups* do volume PostgreSQL (`soc-xpert-db`).
- [ ] Porta de syslog (514) exposta apenas à rede das firewalls.

### O que continua à tua responsabilidade

A aplicação está endurecida, mas uma implantação segura depende também do
ambiente: terminação TLS, gestão de segredos, *backups*, segmentação de rede,
e validação dos conectores contra os teus sistemas reais. Para clientes
empresariais, o SSO/OIDC (Keycloak) entra na sub-fase **03.6**.

---

<div align="center">
<sub>SOC Xpert v1.0 — desenvolvido para o ecossistema Sec4data · Cyber Defense</sub>
</div>
