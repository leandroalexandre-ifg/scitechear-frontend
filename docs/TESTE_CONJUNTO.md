# Teste conjunto — preparo do lado do app

**Data:** 07/09/2026
**Par deste documento:** "Teste conjunto com o backend no NumbERS — preparação"
(lado do backend), que descreve o túnel, as contas, o `smoke_contrato` e o
journal. Aqui está só o que é do app.

O app **não muda** para este teste: nenhum código, nenhuma build especial além
dos dois `--dart-define` que já existiam. O que muda é o que responde do outro
lado de `127.0.0.1:8000`, e o app não sabe a diferença — que é justamente o
motivo de o túnel SSH ter sido a escolha.

> **Atualização — 21/09/2026.** Existe agora uma segunda rota, mais curta:
> o servidor responde na porta 443 da internet pública, então o aparelho
> pode falar direto com ele por HTTPS/WSS, **sem túnel, sem `adb reverse` e
> sem VPN**. O roteiro abaixo continua válido para as duas — muda só o
> comando da seção 1 e o pré-requisito de rede. A rota por túnel segue útil
> para testar contra um backend que não está publicado.

## Estado — 07/09/2026

**Os passos 3 a 7 do roteiro passaram**, contra a API implantada com o worker
rodando: as duas contas cadastradas e logadas pelo app, participante com
amostra de voz, uma reunião de 40 segundos processada até `done`, e o
isolamento confirmado nos dois sentidos (conta B vazia, conta A intacta ao
voltar).

Falta, e o documento continua servindo para isso: **reunião longa (>10 min)**,
que é também a chance de a detecção de truncamento aparecer, e o **passo 8**
da seção 4 (reinstalar e ver o cadastro voltar). O resto abaixo permanece
válido — o roteiro é para repetir, não para arquivar.

---

## 1. Comando

**Rota direta (preferida).** Basta o aparelho ter internet — nenhum
pré-requisito de túnel ou VPN:

```bash
flutter run -d <device-id> \
  --dart-define=SCITECH_API_BASE_URL=https://<ip-do-servidor> \
  --dart-define=SCITECH_WS_BASE_URL=wss://<ip-do-servidor>
```

A confiança no certificado da CA interna vem embutida na build; não é
preciso instalar nada no aparelho (ver seção 4.6 de
[`FRONTEND_ARCHITECTURE.md`](FRONTEND_ARCHITECTURE.md)).

**Rota por túnel.** Com a VPN ligada, o túnel de pé e o `adb reverse`
aplicado (passos 1–4 do documento do backend), com o aparelho conectado:

```bash
flutter run -d <device-id> \
  --dart-define=SCITECH_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=SCITECH_WS_BASE_URL=ws://127.0.0.1:8000
```

Os dois defines são obrigatórios: sem eles o app cai no default de emulador
(`10.0.2.2`), que num aparelho físico não é lugar nenhum.

**Não passe `SCITECH_DEMO_MODE`.** Ele é desligado por padrão, e é assim que
tem que ficar: com ele ligado, uma falha de rede vira transcrição plausível e
o teste inteiro perde o sentido. Se em algum momento aparecer resultado sem o
servidor responder, é a flag, não o backend.

Deixe `scripts/watch-adb-reverse.sh` rodando numa aba: o `adb reverse` cai
quando o cabo tosse, e reaplicá-lo à mão no meio de uma gravação é como se
perde uma rodada.

---

## 2. Se aparecer "Sem conexão com o servidor"

Essa mensagem é o polling desistindo depois de 4 tentativas. Ela **não
distingue** app, `adb reverse`, túnel SSH ou VPN — para o app, todos os quatro
são "não consegui falar com o servidor".

Antes de investigar o app, refaça a cadeia de trás para frente:

```bash
curl -s http://127.0.0.1:8000/health   # na máquina de dev: túnel + VPN
adb reverse --list                     # a linha tcp:8000 tem que estar lá
```

O `ssh -N -L` cai em silêncio quando a VPN oscila, e o sintoma no aparelho é
idêntico ao de um bug do app. É o espelho do que o backend escreveu: se o
`smoke_contrato` está verde, comece pelo app; se o `/health` não responde, nem
olhe para o app.

---

## 3. O que observar em cada passo

**Passo 3 — cadastrar as duas contas.** Feito pelo app, com
`<seu-usuario>+a@ifg.edu.br` e `+b@` — plus-addressing evita precisar de duas
caixas de correio, e o backend não verifica o e-mail. O `+` passa no
validador local do app
(verificado). O app checa formato e mínimo de 8 caracteres **antes** de enviar,
então erro de digitação não gasta tentativa do balde compartilhado.

**Não teste o 403 de domínio errado agora.** Ele conta como falha no balde por
IP, que com o túnel é um só para tudo — dez enganos travam o cadastro por uma
hora, para as duas contas e para o `smoke_contrato`. Ele está coberto por
teste automatizado. Se quiser vê-lo na tela, faça **depois** do passo 7, quando
um bloqueio de uma hora não custa nada: o erro deve aparecer **no campo do
e-mail**, com o texto do servidor, e não num snackbar.

**Passo 4 — participante com voz + reunião longa.** Dois observáveis nossos:

- A amostra de voz sobe no cadastro, não na reunião. Se a rede cair aí, a tela
  avisa que ficou local e o envio é retomado quando a tela reabrir.
- Se o gravador do Android morrer no meio (o bug do Samsung), o app detecta e
  oferece enviar o trecho recuperado. Se isso acontecer, **aceite** — é a
  primeira chance de ver o caminho funcionando, e o backend já sabe que pode
  receber um áudio mais curto que a reunião.

**Passo 5 — acompanhar até `done`.** `identifying` provavelmente não vai
aparecer (0,07s, menos que o intervalo de 1s do WebSocket). Isso é o
comportamento documentado, não estágio pulado nem tela travada — a lista marca
como concluído tudo que ficou para trás. `summarizing` também não aparece,
está desligado por flag.

Se o WebSocket cair, a tela continua andando pelo polling e nada na interface
denuncia a troca. O journal do servidor é que diz se o WS fechou, e por quê.

**Passos 6 e 7 — isolamento.** Provam mais do que provavam quando o roteiro
foi escrito. Ao entrar com a conta B, o app chama `GET /participants` — então
uma lista vazia para B agora significa duas coisas: o armazenamento local está
escopado **e** o servidor não vaza participantes de A para o token de B. Se
aparecer alguém de A na conta B, o problema é do servidor, não do aparelho.

---

## 4. Um passo 8 opcional, se sobrar tempo

Desinstalar o app, reinstalar e entrar com a conta A. **Os participantes de A
devem reaparecer sozinhos, com a voz já cadastrada e nada para regravar** — é
o `GET /participants` semeando o cadastro.

Vale porque é o código mais novo dos dois lados, entrou hoje, e é o que impede
que reinstalar deixe perfis de voz órfãos no servidor. Custa dois minutos e
não suja nada: se falhar, o pior caso é o cadastro voltar vazio, e aí basta
recadastrar.

Não está no roteiro combinado. Os passos 1–7 já passaram (07/09/2026), então
este é o próximo, junto com a reunião longa.

---

## 5. Se algo falhar, o que capturar

Do lado do app, três coisas, nessa ordem de utilidade:

1. **A tela.** Título e mensagem do erro, e o **código em fonte pequena
   embaixo** quando houver — é o `error.code` do backend, e é o que casa com o
   journal do worker.
2. **O console do `flutter run`.** Fica aberto o teste inteiro; é onde
   aparecem exceções que a tela engoliu.
3. **O `job_id`**, que a tela de processamento mostra o tempo todo. É a chave
   para achar tudo no journal e no banco.

---

## 6. O que este teste prova do nosso lado

O que 43 testes com adaptador HTTP falso não podem provar: que a conversa
real acontece. Sessão sobrevivendo ao ciclo de vida do app, renovação de token
antes de um upload multipart (o caminho que existe justamente para não ter que
reenviar um corpo já consumido), WebSocket com `?token=` atravessando dois
túneis, e o escopo por usuário com duas contas de verdade no mesmo aparelho.

O que ele não prova, **quando rodado pela rota do túnel**: nada sobre rede
real. Ali continua tudo em loopback, e a tela nunca terá visto TLS.

Pela rota direta isso deixou de valer — o tráfego é HTTPS/WSS de verdade
sobre a internet pública. A pilha TLS do app foi validada em 21/09/2026
(seção "Validação ponta a ponta" de
[`FRONTEND_ARCHITECTURE.md`](FRONTEND_ARCHITECTURE.md)), mas o que foi
exercitado ali foi o handshake, não a jornada completa. Rodar este roteiro
inteiro pela rota direta é o que fecha essa lacuna — e é a razão de o
documento continuar servindo.
