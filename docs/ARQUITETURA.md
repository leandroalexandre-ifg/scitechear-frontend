# SciTech Ear — Documento de Arquitetura

**Instituto Federal de Goiás · Projeto SciTech**
Aplicativo de captação e análise de reuniões com IA
Organização: Prof. Leandro Alexandre Freitas — Inhumas, Goiás

> Documento vivo: esta é uma versão de trabalho da arquitetura, que evolui junto com o projeto. Alguns componentes descritos (como o Gerenciador de Amostras e o banco de vozes) fazem parte da arquitetura-alvo do backend e ainda não estão implementados.

## 1. Resumo executivo

O SciTech Ear é um aplicativo multiplataforma, desenvolvido em Flutter, para captar o áudio de uma reunião e transformá-lo em conhecimento útil: uma transcrição com identificação de quem falou e uma lista das perguntas levantadas durante o encontro. O processamento pesado de inteligência artificial não ocorre no aparelho — o app é, por decisão de projeto, um cliente fino que grava, envia e exibe. Todo o trabalho de transcrição, diarização e extração de perguntas é delegado a um backend com GPU.

**Estado atual do repositório.** Este documento reflete o que existe de fato no código-fonte avaliado. O repositório contém apenas o aplicativo cliente (Flutter), já com uma arquitetura em camadas bem definida, fluxo de seis telas, autenticação local simulada, gravação em segundo plano e integração de rede pronta para consumir o backend. O backend em si (FastAPI + pipeline de IA) ainda não faz parte deste repositório — ele é um projeto separado, cujo contrato de comunicação já está determinado pelo código do app.

## 2. Visão geral do sistema

O sistema é composto por duas grandes partes que se comunicam pela rede: o aplicativo cliente e o backend de IA.

### 2.1. Aplicativo cliente (este repositório)

Escrito em Flutter/Dart, roda em Android e iOS a partir de uma única base de código. Suas responsabilidades são: autenticar o usuário, configurar a reunião (título e participantes, incluindo uma amostra de voz de cada um), captar o áudio em formato adequado, enviá-lo ao backend, acompanhar o andamento do processamento e apresentar o resultado final.

### 2.2. Backend de IA (repositório separado, ainda não implementado)

Previsto para rodar em um servidor com GPU, expõe uma API (FastAPI), enfileira o trabalho de forma assíncrona (Celery + Redis) e executa o pipeline de processamento. O app já está programado para conversar com esse backend; basta que o servidor honre o contrato descrito na seção 5.

O pipeline organiza-se em etapas. No mesmo nível da transcrição (Frente 1) atua o Gerenciador de Amostras; em seguida vêm a diarização e a extração de perguntas:

- **Frente 1 · Whisper — transcrição.** Converte o áudio da reunião em texto.
- **Gerenciador de Amostras.** Recebe as amostras de voz dos participantes (enviadas pelo app no upload), extrai o embedding de cada uma (via pyannote) e as grava no banco de amostras de voz. Fica no mesmo nível da Frente 1.
- **pyannote.audio — diarização.** Identifica quem falou em cada trecho, comparando as vozes da reunião com os embeddings de referência guardados no banco. É isso que permite nomear os falantes, em vez de usar rótulos genéricos.
- **Frente 2 · Ollama + RAG — extração de perguntas.** Junta o texto ao falante (merge) e, com um modelo de linguagem local apoiado por RAG, extrai as perguntas da reunião.

**Banco de amostras de voz:** é um repositório de vozes de referência — os embeddings extraídos das amostras dos participantes. O Gerenciador de Amostras o alimenta (grava) e a diarização o consulta. A tecnologia do banco ainda não está definida; por ora ele é tratado de forma genérica na arquitetura.

## 3. Estrutura do código

O projeto organiza o código em quatro camadas dentro da pasta `lib/`, com separação clara de responsabilidades. Essa organização é o coração da arquitetura do app.

```
lib/
├── main.dart                     bootstrap: inicializa auth e decide a tela inicial
├── config.dart                   URLs do backend (HTTP e WebSocket)
├── core/theme/                   cores e tema visual (modo escuro)
│   ├── app_colors.dart
│   └── app_theme.dart
├── models/                       estruturas de dados
│   ├── user.dart                 AppUser
│   ├── participant.dart          Participante + amostra de voz
│   ├── meeting.dart               Reunião (título, histórico)
│   └── meeting_result.dart       TranscriptSegment, Question, MeetingResult
├── services/                     lógica de negócio e integração
│   ├── auth_service.dart          login/cadastro (mock local)
│   ├── audio_service.dart         gravação WAV via pacote record
│   ├── background_service.dart    foreground service (Android) + wakelock
│   ├── upload_service.dart        envio multipart do áudio
│   ├── status_service.dart        WebSocket + polling + resultado
│   ├── meeting_service.dart       histórico e persistência de reuniões
│   ├── participant_service.dart   cadastro/gerência de participantes
│   └── offline_service.dart       fallback de demonstração sem backend
├── screens/                      as telas do fluxo
│   ├── auth_screen.dart
│   ├── home_screen.dart
│   ├── meeting_setup_screen.dart
│   ├── participants_screen.dart
│   ├── recording_screen.dart
│   ├── processing_screen.dart
│   └── result_screen.dart
└── widgets/                      componentes visuais reutilizáveis
    ├── glass_card.dart
    ├── gradient_button.dart
    ├── icon_btn.dart
    ├── participant_avatar.dart
    └── voice_sample_sheet.dart
```

**Camadas e responsabilidades:** a regra que organiza o código é simples — as telas (`screens`) cuidam da interface e do fluxo; os serviços (`services`) concentram a lógica de gravar, enviar e acompanhar; os modelos (`models`) representam os dados e espelham o formato que o backend devolve; e os widgets são peças visuais reutilizáveis. Essa separação facilita manutenção e testes.

### 3.1. As quatro camadas

| Camada | Papel |
|---|---|
| Telas (`screens`) | Interface e navegação. Cada tela é um passo do fluxo do usuário. |
| Serviços (`services`) | Lógica de negócio: autenticação, gravação, execução em segundo plano, upload e acompanhamento de status. |
| Modelos (`models`) | Estruturas de dados. As classes de resultado espelham o JSON do backend, com desserialização segura (tolerante a campos ausentes). |
| Widgets | Componentes visuais reutilizáveis (cartões, botões, avatares) que dão identidade ao app. |

**Nota sobre gerência de estado:** não há um gerenciador de estado formal (como Provider ou Riverpod). As dependências (ex.: `AuthService`) são passadas manualmente entre telas via construtor. Funciona bem na escala atual do app — ver recomendação na seção 7.

## 4. Fluxo do usuário

A experiência percorre as telas do app, cada uma acionando os serviços apropriados:

```
AuthScreen → HomeScreen → MeetingSetupScreen → ParticipantsScreen → RecordingScreen → ProcessingScreen → ResultScreen
```

| Tela | O que faz | Serviços acionados |
|---|---|---|
| `AuthScreen` | Login ou cadastro do usuário. | `AuthService` |
| `HomeScreen` | Boas-vindas, histórico de reuniões e ponto de partida para uma nova reunião. | `AuthService`, `MeetingService` |
| `MeetingSetupScreen` | Define título da reunião. | `MeetingService` |
| `ParticipantsScreen` | Cadastra participantes; cada um pode gravar uma amostra de voz. | `ParticipantService`, `AudioService` |
| `RecordingScreen` | Grava o áudio da reunião e, ao encerrar, envia ao backend. | `AudioService`, `BackgroundService`, `UploadService` |
| `ProcessingScreen` | Acompanha o andamento do job em tempo real, com fallback offline de demonstração. | `StatusService`, `OfflineService` |
| `ResultScreen` | Exibe a transcrição (com falantes) e as perguntas, em abas. | — |

**Sobre as amostras de voz.** Um detalhe de arquitetura relevante: na configuração de participantes, cada um pode gravar uma amostra da própria voz. Essas amostras são enviadas junto com o áudio da reunião, com a intenção de que o backend as use para melhorar a diarização — associando cada trecho a uma pessoa nomeada, não apenas a um rótulo genérico de locutor.

## 5. Contrato de comunicação com o backend

Como o app já está pronto para consumir o backend, é o código do cliente que define o contrato que o servidor precisará cumprir. Documentá-lo aqui é essencial para quando o backend for implementado.

### 5.1. Endpoints esperados

| Método | Rota | Descrição |
|---|---|---|
| `POST` | `/upload` | Recebe o áudio (multipart) e as amostras de voz dos participantes. Retorna um `job_id`. |
| `GET` | `/status/{job_id}` | Estado atual do processamento (usado no polling). |
| `GET` | `/resultado/{job_id}` | Resultado final: transcrição e perguntas. |
| `WS` | `/ws/{job_id}` | Canal WebSocket para progresso em tempo real. |

Os estados de processamento previstos, nesta ordem, são: `queued` (na fila), `transcribing` (transcrevendo), `diarizing` (diarizando), `extracting` (extraindo perguntas), `done` (concluído) e `error` (falha).

### 5.2. Formato do resultado

O app espera receber, em `/resultado/{job_id}`, um JSON com duas listas — os trechos da transcrição e as perguntas:

```json
{
  "job_id": "abc123",
  "status": "done",
  "segments": [
    { "speaker": "SPEAKER_00", "start": 0.0, "end": 4.2, "text": "Bom dia." }
  ],
  "questions": [
    { "speaker": "SPEAKER_01", "time": 12.5, "text": "Qual o prazo?" }
  ]
}
```

## 6. Decisões de arquitetura

### 6.1. Cliente fino

O processamento de IA fica inteiramente no servidor. O app apenas capta, envia e exibe. Isso mantém o aplicativo leve, funciona em aparelhos modestos e centraliza o uso da GPU. É a decisão estruturante de todo o projeto.

### 6.2. Flutter em vez de aplicação web

A escolha do Flutter foi motivada por um requisito que navegadores não atendem de forma confiável: gravar áudio com a tela bloqueada. No Android, isso exige um foreground service com uma notificação persistente; sem ele, o sistema encerra a captura ao bloquear a tela. O app declara esse serviço no manifesto (com o tipo de serviço `microphone` e as permissões necessárias) e usa wakelock para manter o processo ativo. No iOS, o mesmo é obtido pela configuração de áudio em segundo plano.

### 6.3. Gravação em WAV 16 kHz mono

O áudio é gravado exatamente no formato que o Whisper e o pyannote esperam — WAV, 16 kHz, mono. Gravar já no formato certo evita conversões no servidor e simplifica o pipeline.

### 6.4. Status em tempo real com WebSocket e fallback

Para acompanhar o processamento, o app tenta primeiro um canal WebSocket, que dá atualizações imediatas. Se ele falhar, o app automaticamente recorre ao polling (consultas periódicas a cada três segundos). Essa estratégia com plano B torna a experiência resiliente a redes instáveis.

### 6.5. Stack técnica

| Área | Pacote | Função |
|---|---|---|
| Gravação | `record` | Captura WAV/PCM, multiplataforma. |
| Background (Android) | `flutter_background` + `wakelock_plus` | Mantém a gravação ativa com a tela bloqueada. |
| Rede | `dio` | Upload multipart com progresso e chamadas HTTP. |
| Tempo real | `web_socket_channel` | Status ao vivo, com fallback de polling. |
| Sessão | `shared_preferences` | Guarda usuário e token localmente. |
| Permissões | `permission_handler` | Microfone e notificações. |
| UI | `google_fonts` + `flutter_animate` | Tipografia e animações. |

## 7. Observações e recomendações

- **Autenticação é simulada.** O login atual é um mock local, com um usuário fixo e aceitação de contas dinâmicas, sem backend de autenticação real. Isso é adequado para desenvolvimento, mas precisará de um serviço de autenticação de verdade antes de qualquer uso além de testes.
- **Configuração do endereço do backend.** O endereço do servidor está fixo no código (`config.dart`), apontando para o localhost do emulador. Para dispositivos físicos e produção, vale considerar torná-lo configurável em tempo de execução, em vez de exigir recompilação.
- **Gerência de estado.** O app hoje passa dependências manualmente entre telas. Funciona bem nesta escala; se o app crescer, um gerenciador de estado (como Provider ou Riverpod) reduziria esse acoplamento.
- **Ausência de testes automatizados.** Há apenas o teste widget padrão gerado pelo Flutter. Conforme o app amadurece, testes dos serviços (sobretudo do upload e do acompanhamento de status) trariam segurança para evoluir sem regressões.
- **Backend é o próximo grande passo.** Com o cliente maduro e o contrato bem definido, o caminho natural é implementar o backend honrando exatamente os endpoints e o formato de resultado da seção 5.

## 8. Glossário

| Termo | Significado |
|---|---|
| Cliente fino | App que só capta, envia e exibe; o processamento pesado fica no servidor. |
| Foreground service | Serviço Android com notificação persistente que impede o sistema de encerrar a gravação. |
| Diarização | Separação do áudio por locutor: quem falou e quando. |
| `job_id` | Identificador do trabalho de processamento, devolvido pelo backend no upload. |
| Polling | Consultas periódicas ao servidor para checar o status (plano B do WebSocket). |
| Multipart | Formato de envio HTTP que agrupa arquivo(s) e campos em uma só requisição. |
| RAG | Geração aumentada por recuperação; dá contexto ao modelo sem re-treiná-lo. |
| Mock | Implementação simulada, usada em desenvolvimento no lugar do serviço real. |
| Amostra de voz | Pequena gravação da voz de um participante, usada como referência para a diarização. |
| Embedding de voz | Representação numérica (vetor) do timbre de uma voz, que permite compará-la com outras. |
| Gerenciador de Amostras | Componente do backend que extrai os embeddings das amostras e os grava no banco de vozes. |
| Banco de amostras de voz | Repositório dos embeddings de referência dos participantes, consultado pela diarização. |
