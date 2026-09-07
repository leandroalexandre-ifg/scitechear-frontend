# SciTech Ear — Arquitetura do Frontend

> Complementa o [`docs/ARCHITECTURE.md`](./ARCHITECTURE.md) (visão geral do
> sistema, com glossário — leia-o primeiro se ainda não leu). Este documento
> detalha o repositório `scitechear`: cada tela, cada serviço, e o
> raciocínio por trás das decisões que moldaram essa estrutura.

## 1. O papel do aplicativo: cliente fino

Antes de entrar nos detalhes de cada arquivo, vale fixar o princípio que
organiza todo o resto: **este aplicativo não processa inteligência
artificial nenhuma.** Ele grava áudio, envia ao backend, acompanha o
progresso, e exibe o que recebe de volta. Nenhuma transcrição, nenhuma
identificação de voz, nenhuma extração de pergunta acontece no aparelho.
Essa escolha existe por dois motivos: manter o aplicativo leve o
suficiente para rodar em qualquer telefone comum, e concentrar o uso da
GPU (recurso caro e escasso) inteiramente no servidor.

Uma consequência direta disso é que a maior parte do código do app não
está resolvendo problemas de IA — está resolvendo problemas de engenharia
de aplicativo móvel: gravar áudio de forma confiável mesmo com a tela
bloqueada, lidar com conexão instável, e apresentar de forma clara um
processamento que pode levar minutos.

## 2. Visão geral

![Arquitetura do frontend](diagrams/05-frontend-architecture.svg)

O código está organizado em três camadas dentro de `lib/`: **telas**
(`screens/`, a interface e o fluxo de navegação), **serviços**
(`services/`, a lógica de integração com o backend e com recursos do
aparelho), e **modelos** (`models/`, as estruturas de dados que espelham o
contrato do backend). Diferente do backend, aqui não há uma camada de
"repositório" formal — o estado local relevante (cache de resultados,
sessão do usuário) é gerenciado dentro dos próprios serviços.

## 3. Fluxo de telas

O aplicativo segue um fluxo linear, tela após tela, sem um framework de
gerenciamento de estado global (como Provider, Riverpod ou Bloc) — as
dependências (como o serviço de autenticação) são passadas explicitamente
de uma tela para a seguinte, através dos construtores dos widgets. Essa é
uma escolha deliberadamente simples: para o tamanho atual do aplicativo,
introduzir uma camada de gerenciamento de estado traria mais complexidade
do que benefício. Se o app crescer substancialmente, essa é uma decisão
que vale revisitar.

### 3.1. `AuthScreen` — entrada

Login e cadastro do usuário. Hoje é uma implementação simplificada, sem um
backend de autenticação real por trás — uma limitação conhecida e
aceitável para a V1, que deverá ser substituída por autenticação de
verdade antes de qualquer uso além de testes internos.

### 3.2. `HomeScreen` — ponto de partida

Mostra o histórico de reuniões já realizadas e é o ponto de partida para
iniciar uma nova. Também é responsável por reabrir uma reunião já
processada anteriormente (buscando o resultado em cache local ou,
se necessário, consultando o backend de novo). Esta tela segue a mesma
regra de tratamento de erro das telas de gravação e processamento
(seção 6): se não conseguir carregar uma reunião do histórico, mostra um
erro real, nunca inventa um conteúdo.

### 3.3. `MeetingSetupScreen` — antes de gravar

Onde o título da reunião é definido e os participantes são selecionados
ou cadastrados (em `ParticipantsScreen`). Ter participantes na lista, ou
que algum deles tenha voz cadastrada, **não é obrigatório para iniciar a
gravação** — o botão "Iniciar Gravação" fica sempre habilitado. Essa é uma
decisão deliberada, não uma omissão: a identificação por voz já é opcional
por design do lado do backend (seção 7 de
[`docs/ARCHITECTURE.md`](./ARCHITECTURE.md#7-por-que-diarização-e-identificação-são-etapas-separadas)) —
quem não tem amostra cadastrada aparece no resultado com o rótulo genérico
do cluster, e o processamento continua normalmente. Exigir participantes
no cliente antes de deixar o usuário começar a gravar seria replicar, na
UI, uma restrição que o backend nunca teve.

É em `ParticipantsScreen`, através do bottom sheet `VoiceSampleSheet`, e
só ali, que uma amostra de voz é gravada e sincronizada com o backend —
nunca durante a gravação da reunião em si. A captura dura 20 segundos
(constante `_maxSeconds` em `voice_sample_sheet.dart` — única fonte de
verdade; o cronômetro e a barra de progresso são calculados a partir
dela, não duplicados). Durante a gravação, uma frase-guia fica visível na
tela para o usuário ler em voz alta — ajuda a capturar uma amostra mais
consistente do que pedir para a pessoa "falar algo" sem roteiro. O rótulo
da tela foi renomeado de "Cadastrar participante" para "Cadastro de
Biometria da Voz", para deixar explícito que aquele fluxo é sobre biometria
de voz do participante — distinto do cadastro de usuário do próprio app
(`AuthScreen`), que é outro conceito e não deve ser confundido com este.

### 3.4. `RecordingScreen` — durante a reunião

Grava o áudio (WAV, 16kHz, mono, o formato exato que o backend espera) e,
ao finalizar, envia ao servidor. Reflete o princípio da seção 6: se o
envio falhar, o erro real é mostrado, com a opção de tentar reenviar o
mesmo arquivo já gravado (sem precisar regravar a reunião do zero).

**Bug crítico encontrado e corrigido: truncamento silencioso de reuniões
longas.** Vale registrar em detalhe porque a causa é sutil e
pode reaparecer se `audio_service.dart` for mexido sem essa memória. O
sintoma: uma reunião gravada por minutos (testado com mais de 3 minutos,
em um tablet Samsung) resultava em um arquivo de áudio válido, mas com
apenas ~45 segundos de duração — sem nenhum erro visível no app, em
nenhum momento. A causa raiz está inteiramente no lado nativo do pacote
`record`, e o app nunca tinha visibilidade sobre ela:

- `AudioRecorder` (o wrapper do pacote `record`) expõe um
  `onStateChanged()` — um stream de estados (`record`/`pause`/`stop`) que
  também carrega, via `onError` da subscription, qualquer exceção lançada
  pelo gravador nativo. Nem `AudioService` nem `RecordingScreen` nunca
  escutaram esse stream — só o stream de amplitude (`onAmplitudeChanged`)
  era consumido.
- No Android, quando o `AudioRecord` nativo falha em ler o buffer de áudio
  (por exemplo, `AudioRecord.ERROR_DEAD_OBJECT` — um erro documentado,
  comum especificamente em aparelhos Samsung sob otimização agressiva de
  bateria/memória, onde o serviço de áudio do sistema é reiniciado), a
  thread de gravação nativa captura a exceção, finaliza o encoder
  normalmente e escreve um header WAV correto para os dados já
  capturados até aquele ponto. O resultado é um arquivo **válido e
  limpo**, só que **truncado** — não corrompido, não vazio, o que tornava
  o sintoma difícil de associar à causa sem investigar o pacote nativo.
- O erro é, de fato, propagado para o lado Dart (via
  `sendStateErrorEvent`) — mas cai no vazio, porque nada está inscrito em
  `onStateChanged()`. Minutos depois, quando o usuário toca em "parar",
  `_audio.stop()` simplesmente devolve o caminho do arquivo já finalizado,
  sem lançar exceção — do ponto de vista do Dart, tudo pareceu correr bem.

**A correção:** `RecordingScreen` agora escuta `stateStream` durante a
gravação e trata qualquer parada que não tenha partido do usuário
(`_handleUnexpectedStop`): para o cronômetro e a waveform, desliga o
serviço de segundo plano, recupera o arquivo parcial e mostra na hora um
aviso dizendo quanto tempo de fato foi gravado, com a escolha entre
descartar ou enviar o trecho que sobrou. Truncado é melhor do que
perdido — o backend processa normalmente o que receber —, mas quem
decide é o usuário, que é o único que sabe se vale analisar só o começo
da reunião.

Três detalhes do lado nativo que a implementação depende, confirmados em
`record_android` e que valem checar de novo se o pacote for atualizado:

- Em falha, `RecordThread` chama `onFailure(ex)` e, no `finally`,
  `onStop()`. O Dart recebe **os dois** — o erro pela `onError` da
  subscription e o `RecordState.stop` pelo stream. Por isso o tratamento
  tem um guard sincrônico (`_handlingInterruption`), senão rodaria duas
  vezes.
- Uma parada normal, pedida pelo usuário, também emite `RecordState.stop`.
  O que distingue as duas é que `_stopAndUpload` cancela a inscrição
  *antes* de chamar `stop()` — então um `stop` que chegue ao listener é,
  por construção, sempre inesperado.
- Depois da falha, `onStop()` zera o `recorderThread` nativo. A chamada
  seguinte a `stop()` cai no ramo em que a thread já não existe e apenas
  devolve o caminho configurado, sem lançar — é assim que o áudio parcial
  é recuperado. `_currentPath` (o retorno de `start()`) fica como rede de
  segurança para o caso de `stop()` devolver nulo.

Fica em aberto a alternativa mais ambiciosa: em vez de encerrar a
reunião, reiniciar o gravador e concatenar os trechos. Exigiria juntar
WAVs no dispositivo (descartar headers, emendar o PCM, reescrever o
header final) e ainda assim deixaria um buraco de áudio no ponto da
falha. Só vale o custo se a interrupção se mostrar frequente no uso real.

**Achado relacionado, esse já corrigido:** o áudio da reunião estava sendo
gravado em `getTemporaryDirectory()` (diretório de cache do Android,
sujeito a limpeza pelo sistema operacional a qualquer momento), diferente
da amostra de voz, que sempre usou `persistent: true`
(`getApplicationDocumentsDirectory()`). Corrigido para `persistent: true`
também na gravação da reunião — importa especialmente para reuniões
longas (1h+), que passam bem mais tempo em disco, aguardando a gravação
terminar e o upload completar, do que uma amostra de voz de 20 segundos.

### 3.5. `ProcessingScreen` — acompanhando o processamento

Mostra visualmente os seis estágios não-terminais do job
(`queued`, `transcribing`, `diarizing`, `identifying`, `summarizing`,
`extracting`), consultando o status do backend. O estado `error` não é
tratado como mais um passo da lista — vira uma tela de erro própria e
distinta, com título, mensagem específica (vinda do `error.message` do
backend, quando disponível) e as opções de tentar novamente ou voltar.
Um botão explícito de voltar para `HomeScreen` também está disponível
durante o acompanhamento ativo do processamento, não só na tela de erro —
antes, a única saída enquanto o job ainda estava rodando era o gesto de
voltar do sistema. Isso é seguro porque a reunião já é registrada no
histórico local logo no início do job (`queued`, em
`recording_screen.dart`, antes mesmo de navegar para esta tela) — sair
cedo não faz o usuário perder a reunião de vista.

### 3.6. `ResultScreen` — o resultado final

Exibe a transcrição, organizada por segmento e por falante, e as perguntas
extraídas (explícitas e implícitas), em abas. O texto de cada segmento e
de cada pergunta é exibido exatamente como veio do backend, sem
reprocessamento no cliente. O botão de voltar para `HomeScreen`, no
cabeçalho, ganhou um `tooltip` explícito ("Voltar às suas reuniões") — o
comportamento de navegação (limpar a pilha até a tela inicial) já estava
correto, o que faltava era deixar o propósito do ícone óbvio para quem
não reconhece o ícone de casa de cara.

### 3.7. Convenções de campos de texto

Campos de texto livre relevante — título da reunião (`MeetingSetupScreen`,
e o diálogo de renomear em `HomeScreen`) e nome de participante
(`ParticipantsScreen`, e "Nome completo" em `AuthScreen`) — usam
`textCapitalization`, ajustado por campo: `.sentences` para os campos de
título (só a primeira letra do texto maiúscula, já que um título é mais
frase do que uma sequência de palavras próprias) e `.words` para os campos
de nome de pessoa (cada parte do nome capitalizada). E-mail, senha e o
campo de e-mail de destinatário (`ResultScreen`, envio de perguntas) ficam
deliberadamente sem capitalização automática — não faz sentido para
credenciais nem para endereços de e-mail.

Acentuação e cedilha (relevantes porque o app é em português do Brasil)
nunca tiveram um `inputFormatter` bloqueando — não havia nenhum restringindo
caracteres em nenhum campo. Um teste (`test/text_encoding_test.dart`)
cobre o round-trip de nomes acentuados através de `jsonEncode`/`jsonDecode`
(persistência local via `SharedPreferences`) e do `FormData` do dio
(multipart enviado ao backend), como validação de que nenhuma das duas
camadas de codificação corrompe o texto.

## 4. Serviços — a lógica por trás das telas

### 4.1. `participant_service.dart` — identidade e voz

Gerencia os dados do participante localmente e sincroniza a amostra de voz
com o backend através de `POST /participants/{id}/voice-samples`. Um
ponto de design que merece destaque, porque já foi fonte de um bug real
antes de ser corrigido: **a sincronização acontece uma única vez, no
momento do cadastro ou da atualização da amostra — nunca a cada
reunião.** Isso é garantido estruturalmente pelo próprio ponto de chamada:
a função de sincronização só é invocada a partir da tela de cadastro de
participantes, nunca do fluxo de upload de uma reunião. Ao remover um
participante, o serviço tenta, de forma best-effort, solicitar a exclusão
do perfil remoto também — mas a remoção local sempre acontece,
independentemente de o backend estar acessível ou não nesse momento.

### 4.2. `upload_service.dart` — enviando a reunião

Monta a requisição multipart para `POST /upload`: o arquivo de áudio, e a
lista de participantes serializada como um único campo JSON
(`participants`), com `id` e `name` de cada um. Uma versão anterior deste
serviço enviava uma amostra de voz por participante a cada upload de
reunião (`voice_samples[]`) — isso foi removido, já que o cadastro de voz
passou a ser responsabilidade exclusiva de `participant_service.dart`,
feito uma única vez. Erros de rede ou de resposta do servidor são
convertidos em uma exceção tipada (`UploadException`), com mensagens
específicas e acionáveis (timeout, sem conexão, erro retornado pelo
servidor), em vez de um erro genérico indiferenciado.

### 4.3. `status_service.dart` — acompanhando o job

Tenta primeiro um canal WebSocket para receber atualizações de status em
tempo real; se ele falhar ou não estiver disponível, recorre
automaticamente a consultas periódicas por polling (a cada poucos
segundos). Um detalhe de comportamento vale registro porque corrigiu um
bug real encontrado durante o desenvolvimento: **se o WebSocket fechar a
conexão antes de o job chegar a um estado terminal (`done` ou `error`),
isso é tratado exatamente como se fosse um erro de conexão — caindo no
polling — em vez de simplesmente parar de escutar.** Sem esse tratamento,
uma implementação de servidor que fecha a conexão WebSocket após enviar
uma única atualização (um comportamento válido, ainda que minimalista)
faria a tela de processamento travar indefinidamente na primeira
atualização recebida.

### 4.4. `audio_service.dart` e `background_service.dart` — a captação

`audio_service.dart` grava o áudio usando o pacote `record`, configurado
explicitamente para o formato esperado pelo backend. `background_service`
mantém a gravação ativa mesmo com a tela do aparelho bloqueada, no
Android, através de um serviço em primeiro plano (foreground service) com
uma notificação persistente — sem isso, o sistema operacional encerraria a
gravação assim que a tela fosse bloqueada.

Um bug real e sério já foi encontrado aqui, vale registrar em detalhe (ver
também o relato em §3.4, do ponto de vista da tela): o gravador nativo do
Android pode falhar internamente durante uma gravação longa — o caso
observado foi `AudioRecord.ERROR_DEAD_OBJECT`, comum em aparelhos Samsung
sob otimização agressiva de bateria/memória, mas a causa nativa exata pode
variar por fabricante. Quando isso acontece, o pacote `record` finaliza o
arquivo WAV corretamente até aquele ponto (arquivo válido, só que
truncado) e propaga o erro para o Dart através do `onError` de
`AudioRecorder.onStateChanged()` — um stream que `AudioService` não
expunha e que nenhuma tela consumia. `AudioService` agora expõe esse
stream como `stateStream`; `RecordingScreen` já o escuta, mas hoje só para
diagnóstico (loga o evento, não reage) — a reação de verdade (tentar
retomar a gravação, ou avisar o usuário imediatamente que a captura parou
antes do esperado) ainda está pendente. Isso é importante o suficiente
para repetir aqui: **qualquer mudança futura em `audio_service.dart` deve
manter `stateStream` sendo escutado por quem grava a reunião** — é a única
forma que o app tem de saber que o gravador nativo morreu no meio do
caminho.

Também foi corrigido, no mesmo bug: a gravação da reunião usava
`persistent: false` (salvando em `getTemporaryDirectory()`, o cache do
Android, que o sistema pode limpar a qualquer momento), enquanto a
amostra de voz sempre usou `persistent: true`
(`getApplicationDocumentsDirectory()`). Agora ambas usam `persistent:
true` — relevante porque reuniões podem passar mais de uma hora em disco
entre o início da gravação e o upload terminar.

### 4.5. `offline_service.dart` — cache e modo de demonstração

Duas responsabilidades relacionadas, mas distintas:

- **`LocalResultCache`** — guarda localmente o resultado de reuniões já
  processadas, para que `HomeScreen` possa reabri-las sem depender de uma
  nova consulta ao backend.
- **Geração de resultado de demonstração** — produz dados fictícios de
  reunião, usados exclusivamente quando o aplicativo é compilado com a
  flag `SCITECH_DEMO_MODE=true`. Um ponto de design deliberado: a decisão
  de *quando* usar esse gerador fica sempre nos pontos de chamada (as
  telas), nunca dentro da própria função geradora — ela não sabe, e não
  deveria saber, por que está sendo chamada. Isso mantém a política de uso
  do modo demo centralizada e fácil de auditar.

## 5. Modelos de dados

### 5.1. `participant.dart`

O campo `id` é o `participant_id` compartilhado com o backend — a
identidade real do participante em todo o sistema (ver a explicação
completa desse princípio em
[`docs/ARCHITECTURE.md`](./ARCHITECTURE.md#8-por-que-participant_id-e-não-o-nome)).
O campo `voiceProfileSynced` (booleano) indica se a amostra de voz atual
já foi enviada ao backend com sucesso; ele é reiniciado para `false`
automaticamente sempre que uma nova amostra é gravada, garantindo que uma
amostra desatualizada nunca fique marcada como sincronizada por engano.

### 5.2. `meeting_result.dart`

Espelha fielmente o contrato canônico do backend
(seção 9 de [`docs/ARCHITECTURE.md`](./ARCHITECTURE.md)):
`TranscriptSegment` carrega `cluster`, `participant_id`, `speaker`
(agora nulável — nem todo segmento tem uma pessoa identificada),
`identified` e `confidence`; `Question` carrega um `type`
(`explicit` ou `implicit`) e campos de identidade opcionais
(`participant_id`, `speaker`, `time`), que ficam `null` para perguntas
implícitas.

## 6. A regra que estas telas nunca violam

`RecordingScreen`, `ProcessingScreen` e `HomeScreen` compartilham uma
regra de comportamento que atravessa este repositório inteiro: **uma
falha real de comunicação com o backend nunca é convertida, de forma
automática e silenciosa, em um resultado fabricado localmente.** Se o
upload falha, se o processamento retorna erro, se uma reunião do
histórico não pode ser recuperada — o usuário vê isso claramente, com uma
mensagem específica e a opção de tentar novamente ou voltar. O único
caminho por onde dados fictícios aparecem é o modo de demonstração
explícito (seção 4.5), ativado na compilação do aplicativo, nunca como
reação automática a uma falha em produção.

Esta regra existe porque a alternativa — mostrar "algo" na tela mesmo
quando o processamento real falhou — cria uma falsa sensação de que o
sistema funcionou, quando na verdade não funcionou. Isso é
particularmente perigoso em um sistema cujo propósito é justamente
registrar com fidelidade o que foi discutido em uma reunião real.

## 7. Sem mapeamento posicional de falante

Uma segunda regra importante, específica de `ResultScreen`: o rótulo e a
cor exibidos para cada segmento de transcrição e cada pergunta nunca são
derivados da *posição* do participante em uma lista local — são sempre
derivados do `participant_id` ou do `cluster` que o backend devolveu.
Uma versão anterior da tela associava o rótulo `SPEAKER_00` ao primeiro
participante da lista de configuração da reunião, `SPEAKER_01` ao
segundo, e assim por diante — um mapeamento por posição que quebrava
silenciosamente sempre que a ordem dos participantes não coincidia com a
ordem em que o pyannote atribuiu os clusters (o que é o caso na maioria
das vezes, já que a diarização não tem nenhuma noção da ordem em que as
pessoas foram cadastradas no aplicativo). A correção elimina essa
suposição por completo: a identidade exibida vem exclusivamente do
resultado biométrico do backend.

## 8. Configuração

A URL do backend não é mais fixa no código-fonte — é definida em tempo de
build, via `--dart-define`:

```bash
flutter run \
  --dart-define=SCITECH_API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SCITECH_WS_BASE_URL=ws://10.0.2.2:8000
```

`10.0.2.2` é o endereço especial que o Android Emulator usa para alcançar
o `localhost` da máquina host — ou seja, para testar contra um backend
rodando no mesmo computador que roda o emulador. Para um dispositivo
físico conectado à mesma rede, use o IP local da máquina que roda o
backend (por exemplo, obtido com `ipconfig getifaddr en0` em um Mac).

O modo de demonstração é configurado da mesma forma, como uma flag de
compilação e não como um interruptor em tempo de execução:

```bash
--dart-define=SCITECH_DEMO_MODE=true
```

Essa escolha (flag de build, não de runtime) existe para eliminar o risco
de alguém ativar o modo demo para uma apresentação e esquecer de
desativá-lo depois — como é uma flag de compilação, ela não pode
"vazar" silenciosamente para uma instalação de produção sem uma decisão
explícita de build.

## 9. Ambiente de desenvolvimento e testes

Para rodar localmente contra um backend também local, no Android Emulator:

```bash
flutter devices                       # confirme o ID do dispositivo/emulador
flutter run -d <device-id> \
  --dart-define=SCITECH_API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SCITECH_WS_BASE_URL=ws://10.0.2.2:8000
```

Os testes automatizados priorizam a verificação do parsing do contrato de
dados (o JSON que o backend devolve, incluindo casos de borda como
segmentos não identificados e perguntas implícitas com campos nulos) e o
comportamento de fallback de rede (WebSocket falhando e caindo em
polling), em vez de depender de um backend real rodando durante a suíte
de testes.

Testar em dispositivo físico é o caminho recomendado (evita problemas de
captura de áudio específicos do emulador) — o passo a passo completo está
no README, em ["Rodando em dispositivo
físico (Android)"](../README.md#rodando-em-dispositivo-físico-android).
O túnel `adb reverse` precisa ser refeito manualmente sempre que o cabo
USB é desconectado e reconectado; `scripts/watch-adb-reverse.sh` automatiza
isso, ficando em loop e reaplicando o túnel assim que o dispositivo
reaparece — útil para deixar rodando numa aba de terminal separada durante
uma sessão de testes mais longa, em vez de repetir o comando manualmente a
cada desconexão.

## 10. Escopo da V1

Android é a plataforma testada e validada nesta versão — o código
preserva compatibilidade com iOS, mas isso não é critério de aceite da V1.
A autenticação é simplificada (seção 3.1); um serviço de autenticação real
é um passo necessário antes de qualquer uso além de testes internos.
