# SciTech Ear

App Flutter (cliente fino) para gravar reuniões, enviá-las a um backend de IA e exibir a transcrição com identificação de falantes e as perguntas extraídas automaticamente.

Todo o processamento pesado (transcrição, diarização, extração de perguntas) roda no backend — o app apenas grava, envia e exibe o resultado. Quando o backend não está disponível, o app cai automaticamente em um modo de demonstração offline, com um resultado fictício, para permitir apresentar o fluxo completo sem servidor no ar.

> Para o documento completo de arquitetura (diagrama do sistema, camadas, contrato com o backend e recomendações), veja [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

## Arquitetura

```
SciTech Ear (Flutter, este repositório)
  └── Grava áudio WAV 16 kHz mono
  └── Envia via HTTP multipart para o backend
  └── Acompanha o status do job (WebSocket, com fallback para polling)
  └── Exibe transcrição (com falantes) + perguntas extraídas
  └── Se o backend estiver indisponível, gera um resultado de demonstração local

Backend (repositório separado — ainda não implementado)
  └── FastAPI
  └── Whisper   → transcrição
  └── pyannote  → diarização (identificação de falantes)
  └── Ollama    → extração de perguntas a partir da transcrição
```

## Funcionalidades

- **Login** com conta fixa pré-cadastrada (`leandro` / `leandro`, administrador) ou cadastro dinâmico de qualquer usuário/senha (mock local, sem backend de auth ainda)
- **Cadastro de participantes**: registro persistente e reutilizável entre reuniões, cada um podendo gravar uma amostra de voz (usada pelo backend para diarização)
- **Configuração da reunião**: título (editável) e seleção dos participantes que estarão presentes
- **Gravação**: captura de áudio em WAV 16 kHz mono, com visualização de forma de onda em tempo real, funcionando em segundo plano com a tela bloqueada
- **Processamento**: upload multipart do áudio + amostras de voz, com acompanhamento do status (`queued` → `transcribing` → `diarizing` → `extracting` → `done`/`error`)
- **Modo offline de demonstração**: se o backend não responder, o app gera um resultado plausível (usando os nomes reais dos participantes) para não travar a demonstração
- **Histórico de reuniões**: lista local das reuniões já enviadas, com acesso ao resultado de cada uma
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
    upload_service.dart            # upload multipart (áudio + amostras de voz)
    status_service.dart            # WebSocket/polling de status + busca do resultado
    meeting_service.dart           # histórico local de reuniões
    participant_service.dart       # cadastro persistente de participantes
    offline_service.dart           # geração de resultado de demonstração sem backend
  widgets/                         # componentes visuais reutilizáveis (glass card, botão gradiente, avatar)
```

## Configuração do backend

O endereço do backend é definido em `lib/config.dart`:

```dart
static const String backendBaseUrl = 'http://10.0.2.2:8000';
static const String backendWsUrl = 'ws://10.0.2.2:8000';
```

- **Emulador Android**: `10.0.2.2` aponta para o `localhost` da máquina host
- **Dispositivo físico**: use o IP da máquina na rede local (ex.: `192.168.0.10`)
- **Produção**: use o domínio com HTTPS/WSS

## Contrato da API esperada (backend ainda não implementado)

```
POST /upload
  Content-Type: multipart/form-data
  Body: file=<wav>, title?, participant_names[]=, voice_samples[]=<wav>
  Resposta: { "job_id": "uuid" }

GET /status/{job_id}          (fallback de polling)
WS   /ws/{job_id}             (status em tempo real)
  Resposta: { "status": "queued|transcribing|diarizing|extracting|done|error" }

GET /resultado/{job_id}
  Resposta: {
    "job_id": "uuid",
    "status": "done",
    "segments": [{ "speaker": "SPEAKER_00", "start": 0.0, "end": 4.2, "text": "..." }],
    "questions": [{ "speaker": "SPEAKER_01", "time": 12.5, "text": "..." }]
  }
```

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
- Não usar o login mock atual como autenticação real de produção — é um placeholder até o backend de auth existir

## Arquitetura

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
6. Rode o app apontando para `localhost`, via o túnel do adb:
```bash
   flutter run -d <device-id> --dart-define=SCITECH_API_BASE_URL=http://127.0.0.1:8000 --dart-define=SCITECH_WS_BASE_URL=ws://127.0.0.1:8000
```

Se o aparelho for desconectado e reconectado, repita o passo 4 (`adb reverse`).
