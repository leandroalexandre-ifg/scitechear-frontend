# SciTech Ear

App Flutter (cliente fino) para gravar reuniões, enviá-las a um backend de IA e exibir a transcrição com identificação de falantes e as perguntas extraídas automaticamente.

Todo o processamento pesado (transcrição, diarização, extração de perguntas) roda no backend — o app apenas grava, envia e exibe o resultado. Quando o backend não responde, o app mostra o erro real: nunca fabrica um resultado para disfarçar a falha. Existe um modo de demonstração com dados fictícios, mas ele só liga por compilação explícita (`--dart-define=SCITECH_DEMO_MODE=true`).

O app autentica de verdade contra o backend (`/auth/*`, JWT com refresh
token). Ver [Estado da integração](#estado-da-integração).

> Para o documento completo de arquitetura (diagrama do sistema, camadas, contrato com o backend e recomendações), veja [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

## Arquitetura

```
SciTech Ear (Flutter, este repositório)
  └── Grava áudio WAV 16 kHz mono
  └── Envia via HTTP multipart para o backend
  └── Acompanha o status do job (WebSocket, com fallback para polling)
  └── Exibe transcrição (com falantes) + perguntas extraídas
  └── Se o backend estiver indisponível, mostra o erro (não inventa resultado)

Backend (repositório separado — implementado)
  └── FastAPI          → API, com autenticação JWT e dados escopados por usuário
  └── Worker dedicado  → processa a fila de jobs em um processo separado da API
  └── WhisperX         → transcrição
  └── pyannote         → diarização (separação de falantes)
  └── SpeechBrain      → identificação por biometria de voz (ECAPA)
  └── Ollama           → extração de perguntas explícitas e implícitas
```

## Funcionalidades

- **Login e cadastro** contra o `/auth` do backend (JWT + refresh token, senha de no mínimo 8 caracteres). A sessão sobrevive ao fechamento do app e é renovada automaticamente; quando o refresh token é revogado ou expira, o app volta sozinho para a tela de login
- **Cadastro de participantes**: registro persistente e reutilizável entre reuniões, cada um podendo gravar uma amostra de voz (enviada uma única vez ao backend, para identificação por biometria)
- **Configuração da reunião**: título (editável) e seleção dos participantes que estarão presentes
- **Gravação**: captura de áudio em WAV 16 kHz mono, com visualização de forma de onda em tempo real, funcionando em segundo plano com a tela bloqueada. Uma parada inesperada do gravador (falha do aparelho) é detectada na hora, com opção de enviar o trecho recuperado
- **Processamento**: upload multipart do áudio, com acompanhamento do status (`queued` → `transcribing` → `diarizing` → `identifying` → `summarizing` → `extracting` → `done`/`error`)
- **Modo de demonstração**: resultado fictício para apresentar o fluxo sem servidor no ar. Só liga com `--dart-define=SCITECH_DEMO_MODE=true`; nunca é acionado automaticamente por falha de rede
- **Histórico de reuniões**: lista local das reuniões já enviadas, com acesso ao resultado de cada uma (o backend também expõe `GET /meetings`, ainda não consumido pelo app)
- **Resultado**: transcrição com marcação de falante e tempo, e lista de perguntas identificadas na conversa

## Fluxo de telas

```
AuthScreen → HomeScreen → MeetingSetupScreen → ParticipantsScreen → RecordingScreen → ProcessingScreen → ResultScreen
```

`ParticipantsScreen` também é acessível diretamente da `HomeScreen`, como cadastro geral de participantes (fora do fluxo de uma reunião específica).

## Stack técnica

| Área | Pacote/Escolha | Motivo |
|---|---|---|
| Gravação de áudio | `record` | Suporta WAV/PCM, funciona em segundo plano, multiplataforma |
| Execução em segundo plano (Android) | `flutter_background` + `wakelock_plus` | Mantém o áudio ativo com a tela bloqueada |
| Upload/HTTP | `dio` | Multipart upload com progresso |
| Status em tempo real | `web_socket_channel` | WebSocket com fallback de polling |
| Persistência local | `shared_preferences` | Sessão, cadastro de participantes, histórico de reuniões e cache de resultados |
| Permissões | `permission_handler` | Microfone e notificações |
| UI | `google_fonts` (Inter) + `flutter_animate` | Tipografia e animações declarativas |

## Estrutura do projeto

```
lib/
  main.dart                       # bootstrap do app + rota inicial (auth ou home)
  config.dart                     # URLs do backend (HTTP e WebSocket)
  core/theme/                     # cores e tema (dark) do app
  models/
    user.dart                     # AppUser (id, nome, email)
    participant.dart              # Participante cadastrado + amostra de voz
    meeting.dart                  # Meeting (metadados de reunião enviada)
    meeting_result.dart           # TranscriptSegment, Question, MeetingResult (espelha o JSON do backend)
  screens/
    auth_screen.dart               # login / cadastro
    home_screen.dart               # tela inicial, histórico de reuniões, atalhos, logout
    meeting_setup_screen.dart      # título da reunião + seleção de participantes
    participants_screen.dart       # cadastro/gerência de participantes e amostras de voz
    recording_screen.dart          # gravação com forma de onda em tempo real
    processing_screen.dart         # upload + acompanhamento de status (com fallback offline)
    result_screen.dart             # transcrição e perguntas extraídas
  services/
    api_client.dart                # tokens JWT, header Authorization e renovação automática
    local_scope.dart               # escopo por usuário das chaves guardadas no aparelho
    auth_service.dart              # login/cadastro/logout contra /auth do backend
    audio_service.dart             # grava WAV 16kHz mono via `record`
    background_service.dart        # foreground service (Android) + wakelock
    upload_service.dart            # upload multipart do áudio da reunião
    status_service.dart            # WebSocket/polling de status + busca do resultado
    job_errors.dart                # tradução dos códigos de falha de job
    meeting_service.dart           # histórico local de reuniões
    participant_service.dart       # cadastro de participantes (local + GET /participants) e amostras de voz
    offline_service.dart           # cache local de resultados + gerador do modo demo
  widgets/                         # componentes visuais reutilizáveis (glass card, botão gradiente, avatar)
```

## Configuração do backend

O endereço do backend fica em `lib/config.dart` e é definido por
`--dart-define` na compilação, com um default de emulador:

```dart
static const String backendBaseUrl = String.fromEnvironment(
  'SCITECH_API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
static const String backendWsUrl = String.fromEnvironment(
  'SCITECH_WS_BASE_URL', defaultValue: 'ws://10.0.2.2:8000');
```

- **Emulador Android**: `10.0.2.2` aponta para o `localhost` da máquina host
- **Dispositivo físico**: use o túnel do `adb reverse` (ver a última seção) ou o IP da máquina na rede local
- **Produção**: use o domínio com HTTPS/WSS

## Contrato da API

Rotas efetivamente expostas pelo backend. **Todas exigem
`Authorization: Bearer <access_token>`**, exceto `/auth/register`,
`/auth/login`, `/auth/refresh` e `/health`.

```
POST /auth/register          → 201 { id, name, email, ... }
                               403 se o domínio do e-mail não está na
                               allowlist institucional do servidor
POST /auth/login             → { access_token, refresh_token }
POST /auth/refresh           → { access_token, refresh_token }
POST /auth/logout            → 204  (revoga só aquele refresh token)
GET  /auth/me                → { id, name, email, ... }

POST /upload
  Content-Type: multipart/form-data
  Body: file=<wav 16kHz mono>, title?, participants=<json>, expected_speaker_count?
        participants: [{"id": "p1", "name": "José"}, ...]  (campo JSON único)
  Resposta: 202 { "job_id": "uuid", "status": "queued" }
  413 acima de 300 MB (MAX_UPLOAD_MB). O teto é aplicado durante a escrita
  em disco, então o 413 pode chegar com o corpo ainda subindo.

GET /meetings?limit=&offset= → [{ job_id, title, status, created_at, updated_at }]
                               (exposto pelo backend; o app ainda usa histórico local)

GET /status/{job_id}          (polling)
  Resposta: { job_id, status, progress?, error?: {code, message}, updated_at }
  `progress` é SEMPRE null — o backend nunca o escreve. Não construir barra
  de progresso nem percentual em cima dele.

WS  /ws/{job_id}?token=<access_token>
  Autenticação por query param — o handshake de WS não aceita header
  Authorization em todo cliente. Fecha com 4401 sem token, 4404 se o job
  não for do usuário.
  Empurra o estado atual a cada segundo até done/error, com teto de 1h por
  conexão. O cliente lê EM LAÇO — encerrar depois da primeira mensagem
  descartaria o push. O fallback de polling continua obrigatório: removê-lo
  é decisão combinada com o backend (ver o comentário em status_service.dart).

GET /resultado/{job_id}       (409 enquanto o status não for "done")
  Resposta: {
    "job_id": "uuid",
    "status": "done",
    "segments": [{ id, cluster, participant_id?, speaker?, identified,
                   confidence?, start, end, text }],
    "questions": [{ id, type: "explicit"|"implicit", text, participant_id?,
                    speaker?, time?, source_segment_ids[] }],
    "metadata": { whisperx_model, diarization_model, voice_model, llm_model,
                  generated_at, stub }
  }

GET    /participants          (Bearer)
       → [{ participant_id, name, sample_count, model_version, updated_at }]
       Só do usuário autenticado, ordenado por nome e depois por id.
       `name` pode ser null (é opcional no cadastro de amostra); o
       participant_id vem sempre. Lista vazia para quem nunca cadastrou voz.

POST   /participants/{participant_id}/voice-samples   (multipart: file, name?)
       413 acima de 25 MB (MAX_VOICE_SAMPLE_MB)
GET    /participants/{participant_id}/voice-profile
       → { participant_id, exists, sample_count, model_version, updated_at }
       O app não usa: a listagem acima resolve o mesmo em uma chamada.
DELETE /participants/{participant_id}/voice-profile   → 204 SEMPRE,
       inclusive para perfil inexistente. Idempotente por desenho, para não
       revelar a diferença entre "não é seu" e "não existe" — como o
       /auth/logout. É no 204 que a fila de exclusões pendentes desarma.
```

Estados do job: `queued`, `transcribing`, `diarizing`, `identifying`,
`summarizing`, `extracting`, `done`, `error`. O app emite mais dois valores
**inventados pelo cliente**, que o backend nunca envia: `offline` (o polling
esgotou as tentativas) e `removed` (o servidor respondeu 404 — o job não
existe mais para este usuário; terminal, e sem botão de tentar de novo).

**O job não passa necessariamente por todos os oito.** O servidor empurra o
estado *atual* a cada segundo, não a sequência de transições; estágios curtos
(`identifying`, `summarizing`) costumam não aparecer nenhuma vez.
`queued → transcribing → diarizing → extracting → done` é normal e frequente.
Nenhuma tela pode tratar um estado pulado como anomalia.

### `participant_id` é gerado pelo app — e o servidor é quem o preserva

O id sai de `DateTime.now().microsecondsSinceEpoch` no cadastro do
participante e mora em `u<user_id>:registered_participants`, no
`shared_preferences`, que **não sobrevive a reinstalar o app nem a trocar de
aparelho**. Como o id é a única forma de alcançar um perfil de voz, perdê-lo
deixaria a gravação invisível e inapagável no servidor.

Duas coisas impedem isso, e nenhuma das duas é opcional:

- **`GET /participants` semeia o cadastro de volta.** Entrar numa conta com
  cadastro local vazio traz os participantes do servidor, com a voz já pronta
  (`ParticipantService.seedFromServerIfEmpty`, chamado pela tela inicial). O
  usuário reencontra as pessoas em vez de recadastrá-las com ids novos — que
  é o que órfãria os perfis antigos.
- **Um id nunca é descartado sem confirmação.** Quando o
  `DELETE .../voice-profile` falha, ele vai para
  `u<user_id>:pending_voice_profile_deletions` e é retomado na próxima
  abertura da tela de participantes. A retomada roda **antes** da listagem,
  senão o perfil que o usuário mandou apagar voltaria como cadastro.

Não gere `participant_id` em nenhum outro lugar do app.

Um participante semeado tem perfil de voz no servidor e nenhum WAV local — a
pergunta que a tela faz é `hasVoiceProfile`, não `hasVoiceSample`, senão ela
manda o usuário regravar uma voz que já está cadastrada.

### Cadastro restrito a e-mails institucionais

O backend mantém uma allowlist de domínios (`AUTH_ALLOWED_EMAIL_DOMAINS`,
hoje `ifg.edu.br`) e recusa `POST /auth/register` fora dela com **403**. O app
mostra o `detail` do servidor ancorado no campo do e-mail — é condição
permanente do endereço, não algo que melhora tentando de novo.

**O 403 conta como tentativa falha no rate limit**, de propósito (senão daria
para varrer domínios). Errar o domínio 10 vezes trava o cadastro por 1 hora —
e com `adb reverse` o aparelho inteiro é `127.0.0.1`, um balde só para todas
as contas do teste.

### Rate limiting

|  | Escopo | Limite | Janela | `Retry-After` |
|---|---|---|---|---|
| `/auth/login` | por **e-mail** | 5 falhas | 15 min | `900` |
| `/auth/register` | por **IP** | 10 falhas | 60 min | `3600` |

Só falhas contam; um login bem-sucedido limpa o contador daquele e-mail. Uma
tentativa já bloqueada não estende a janela.

O `Retry-After` é **a janela inteira, não o tempo restante** — pode dizer 3600
faltando um minuto. Por isso a mensagem do app é "aguarde até X minutos", um
limite superior, e não uma previsão.

### Códigos de falha de job

`error.code` em `/status/{job_id}` é um conjunto fechado de sete:
`AUDIO_NAO_ENCONTRADO`, `TRANSCRIPTION_ERROR`, `DIARIZATION_ERROR`,
`IDENTIFICATION_ERROR`, `SUMMARIZATION_ERROR`, `EXTRACTION_ERROR`,
`WORKER_MAX_TENTATIVAS_EXCEDIDO` (o job órfão: o worker morreu no meio, o job
foi reenfileirado 3 vezes e o backend desistiu).

O app traduz por `code` em `job_errors.dart`. O `error.message` **nunca** é
exibido: é o `str(exc)` da exceção Python, em inglês e às vezes com caminho de
arquivo do servidor dentro.

## Estado da integração

| Área | Backend | App | Situação |
|---|---|---|---|
| Autenticação | `/auth/*`, JWT (access 30min + refresh 30 dias), Argon2id, rate limiting | `auth_service.dart` + `api_client.dart` | ✅ em dia |
| Rotas protegidas | exigem `Bearer` | injetado pelo interceptor, com renovação automática | ✅ em dia |
| WebSocket | exige `?token=` | token na query string | ✅ em dia |
| Escopo por usuário | jobs e vozes por `user_id` | derivado do token | ✅ em dia |
| Resultado | schema completo | `meeting_result.dart` espelha | ✅ em dia |
| Upload | `participants` como JSON | envia JSON | ✅ em dia |
| Amostra de voz | endpoint dedicado | envia uma vez no cadastro | ✅ em dia |
| Cadastro de participantes | `GET /participants` | semeia o cadastro em instalação nova e reconcilia ao abrir a tela | ✅ em dia |
| Push de progresso | `/ws` empurra até `done`/`error` (Fase 8, validada em 05/09/2026) | lê em laço, com polling como fallback obrigatório | ✅ em dia |
| Histórico | `GET /meetings` | lista local em `shared_preferences` | divergente, migração acordada mas não agendada |
| Dados no aparelho | escopados por `user_id` | chaves escopadas (`local_scope.dart`) | ✅ em dia |
| Papel de administrador | não existe, e não há plano de existir | removido do app | ✅ resolvido |

### Como a sessão funciona

`api_client.dart` é o dono do par de tokens e o único ponto que fala
`Authorization`:

- **Renovação proativa.** Antes de cada requisição, se o access token vence
  em menos de 2 minutos, ele é renovado. O 401 com reenvio existe como
  rede de segurança (token revogado no servidor, relógio fora de hora), não
  como caminho principal.
- **Uma renovação por vez.** Chamadas concorrentes com o token vencido
  compartilham o mesmo `/auth/refresh`. O backend revoga o refresh token no
  uso (rotação estrita, sem janela de graça — confirmado em 07/09/2026), então
  N renovações paralelas fariam N−1 falharem. Não há detecção de reuso em
  cascata: um refresh que escape da serialização custa uma chamada com 401,
  não a sessão. Se o backend adicionar reuse-detection, isto vira crítico —
  eles avisam antes.
- **Falha de rede não desloga.** Só um 401 no próprio refresh encerra a
  sessão; timeout ou queda de conexão preserva o token para a próxima
  tentativa.
- **Expiração é tratada em um lugar.** `main.dart` escuta
  `ApiClient.onSessionExpired` e leva o usuário de volta ao login, em vez de
  cada tela ter que decidir o que fazer com um 401.

Para apresentar o fluxo sem servidor no ar, o caminho continua sendo
`--dart-define=SCITECH_DEMO_MODE=true`.

## Notas importantes sobre gravação em segundo plano

- **Android**: um foreground service é obrigatório — sem ele, o sistema mata a thread de áudio quando a tela é bloqueada. O `AndroidManifest.xml` declara o serviço com `foregroundServiceType="microphone"` e as permissões `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_MICROPHONE`. Uma notificação persistente é exibida durante a gravação (exigência do sistema).
- **iOS**: a categoria da sessão de áudio permite gravação em segundo plano via `UIBackgroundModes` no `Info.plist`.
- Teste em dispositivo físico ou emulador com bloqueio de tela — alguns emuladores não reproduzem o comportamento de encerramento do sistema.

## Como rodar

```bash
flutter pub get

# Rodar em um dispositivo conectado (prefira Android físico para testar o foreground service)
flutter run

# Analisar o código
flutter analyze

# Rodar os testes
flutter test
```

## O que não fazer

- Não adicionar alvos desktop/web como objetivo — eles existem apenas como scaffold do `flutter create`
- Não processar áudio no dispositivo — todo o ML roda no backend
- Não armazenar gravações permanentemente no dispositivo — enviar e descartar
- Não guardar token fora do `api_client.dart` — uma segunda cópia dessincroniza na primeira renovação, e o app passa a alternar entre chamadas válidas e 401
- Não criar `Dio` avulso para falar com o backend: use `ApiClient.instance.client()`, senão a requisição sai sem `Authorization`
- Não gravar chave nova em `shared_preferences` com nome fixo — passe por `LocalScope.key()`, senão o dado fica visível para qualquer conta que use o aparelho depois
- Não fazer o app cair em resultado fictício quando o backend falha — o modo demo é sempre uma escolha de compilação, nunca um fallback silencioso de rede

## Documentação de arquitetura

Documentação completa da arquitetura, com diagramas, em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (visão geral do sistema) e [`docs/FRONTEND_ARCHITECTURE.md`](docs/FRONTEND_ARCHITECTURE.md) (telas, serviços e modelos deste repositório).

![Fluxo de telas e serviços do frontend](docs/diagrams/05-frontend-architecture.svg)

| Documento | Conteúdo |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Contexto geral, máquina de estados do job, sequência ponta a ponta, contrato de dados |
| [`docs/FRONTEND_ARCHITECTURE.md`](docs/FRONTEND_ARCHITECTURE.md) | Telas, serviços, modelos, configuração via `--dart-define` |

## Rodando em dispositivo físico (Android)

Recomendado sobre o emulador — evita problemas de captura de áudio do emulador.

1. No aparelho: ative "Opções do desenvolvedor" (7x em "Número da versão") e a "Depuração USB".
2. Conecte por cabo USB e autorize o popup de depuração no aparelho.
3. Confirme a conexão:
```bash
   flutter devices
```
4. Redirecione a porta do backend via USB (evita problemas de rede/Wi-Fi):
```bash
   ~/Library/Android/sdk/platform-tools/adb reverse tcp:8000 tcp:8000
```
5. Suba o backend (em outro terminal):
```bash
   cd ~/SciTech-backend && source .venv/bin/activate && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
6. Suba o worker (em um terceiro terminal). Ele é um **processo separado** da
   API: `/upload` só grava o job na fila, quem processa é o worker. Sem ele,
   todo job fica parado em `queued` para sempre:
```bash
   cd ~/SciTech-backend && source .venv/bin/activate && python -m app.worker
```
7. Rode o app apontando para `localhost`, via o túnel do adb:
```bash
   flutter run -d <device-id> --dart-define=SCITECH_API_BASE_URL=http://127.0.0.1:8000 --dart-define=SCITECH_WS_BASE_URL=ws://127.0.0.1:8000
```

Se o aparelho for desconectado e reconectado, repita o passo 4 (`adb reverse`).
Para não precisar repetir manualmente durante uma sessão de testes mais
longa, rode `scripts/watch-adb-reverse.sh` numa aba de terminal separada —
ele fica em loop e reaplica o túnel automaticamente assim que o aparelho
reconectar.
