# SciTech Ear

App Flutter (cliente fino) para gravar reuniões, enviá-las a um backend de IA e exibir a transcrição com identificação de falantes e as perguntas extraídas automaticamente.

Todo o processamento pesado (transcrição, diarização, extração de perguntas) roda no backend — o app apenas grava, envia e exibe o resultado. Quando o backend não responde, o app mostra o erro real: nunca fabrica um resultado para disfarçar a falha. Existe um modo de demonstração com dados fictícios, mas ele só liga por compilação explícita (`--dart-define=SCITECH_DEMO_MODE=true`).

> ⚠️ **O app ainda não fala com o backend atual.** Desde 03/09/2026 o backend
> exige autenticação real (JWT) em *todas* as rotas usadas pelo app, e o
> `auth_service.dart` daqui continua sendo um mock local que nunca emite
> token — ou seja, hoje todas as chamadas voltariam 401. Ver
> [Estado da integração](#estado-da-integração).

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

- **Login** com conta fixa pré-cadastrada (`leandro` / `leandro`, administrador) ou cadastro dinâmico de qualquer usuário/senha — **mock local, ainda não integrado ao `/auth` real do backend**
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
    user.dart                     # AppUser (id, nome, email, isAdmin)
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
    auth_service.dart              # login/cadastro/logout (mock local via shared_preferences)
    audio_service.dart             # grava WAV 16kHz mono via `record`
    background_service.dart        # foreground service (Android) + wakelock
    upload_service.dart            # upload multipart do áudio da reunião
    status_service.dart            # WebSocket/polling de status + busca do resultado
    meeting_service.dart           # histórico local de reuniões
    participant_service.dart       # cadastro de participantes + envio da amostra de voz
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
POST /auth/login             → { access_token, refresh_token }
POST /auth/refresh           → { access_token, refresh_token }
POST /auth/logout            → 204
GET  /auth/me                → { id, name, email, ... }

POST /upload
  Content-Type: multipart/form-data
  Body: file=<wav 16kHz mono>, title?, participants=<json>, expected_speaker_count?
        participants: [{"id": "p1", "name": "José"}, ...]  (campo JSON único)
  Resposta: 202 { "job_id": "uuid", "status": "queued" }

GET /meetings?limit=&offset= → [{ job_id, title, status, created_at, updated_at }]
                               (exposto pelo backend; o app ainda usa histórico local)

GET /status/{job_id}          (polling)
  Resposta: { job_id, status, progress?, error?: {code, message}, updated_at }

WS  /ws/{job_id}?token=<access_token>
  Autenticação por query param — o handshake de WS não aceita header
  Authorization em todo cliente. Fecha com 4401 sem token, 4404 se o job
  não for do usuário.
  ATENÇÃO: ainda é um stub — manda o status atual UMA vez e fecha. O push
  real de progresso é Fase 8 do backend, então o fallback de polling
  continua obrigatório (ver o comentário em status_service.dart).

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

POST   /participants/{participant_id}/voice-samples   (multipart: file, name?)
GET    /participants/{participant_id}/voice-profile
DELETE /participants/{participant_id}/voice-profile   → 204
```

Estados do job: `queued`, `transcribing`, `diarizing`, `identifying`,
`summarizing`, `extracting`, `done`, `error`. O app também emite um
`offline` **inventado pelo cliente** quando o polling esgota as tentativas —
o backend nunca envia esse valor.

## Estado da integração

O contrato de dados do resultado já está em sincronia: `meeting_result.dart`
espelha exatamente o schema atual do backend. O que falta é autenticação.

| Área | Backend | App | Situação |
|---|---|---|---|
| Autenticação | `/auth/*` com JWT (access + refresh), Argon2id, rate limiting | mock local em `auth_service.dart`, sem token | **bloqueante** |
| Rotas protegidas | todas exigem `Bearer` | nenhuma chamada envia header | **bloqueante** — 401 |
| WebSocket | exige `?token=` | conecta sem token | **bloqueante** — fecha 4401 |
| Escopo por usuário | jobs e vozes por `user_id` | assume dados globais | depende da auth |
| Resultado | schema completo | `meeting_result.dart` espelha | ✅ em dia |
| Upload | `participants` como JSON | envia JSON | ✅ em dia |
| Amostra de voz | endpoint dedicado | envia uma vez no cadastro | ✅ em dia |
| Histórico | `GET /meetings` | lista local | divergente, não bloqueante |

Enquanto a autenticação real não entrar no app, o caminho para demonstrar o
fluxo é `--dart-define=SCITECH_DEMO_MODE=true`.

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
- Não usar o login mock atual como autenticação real — o backend de auth **já existe** (`/auth/*`, JWT), então o mock deixou de ser um placeholder à espera e passou a ser o que impede o app de funcionar contra o backend
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
